extends Control

const SCOPE_NODES := [
	"function_declaration",
	"function_definition",
	"local_function_declaration",
	"do_statement",
	"for_statement",
	"while_statement",
	"repeat_statement",
]

const FOLDER_ICON: Texture2D = preload("res://assets/textures/icons/folder_icon.tres")
const FILE_ICON: Texture2D = preload("res://assets/textures/icons/file_icon.tres")
# 树行图标最大宽度（原图 64px，缩至 32px 使行高减半）
const TREE_ICON_MAX_WIDTH := 32
# 黑名单编辑器文本变化后的去抖时长（秒）
const TEXT_UPDATE_DEBOUNCE_TIME := 1.0

var lua_parser:LuaParser = LuaParser.new()
var ast_dump_target:FileAccess = FileAccess.open("res://dump.txt",FileAccess.WRITE_READ)
var root_path:String = ""
var globals_find_result:Dictionary[String,Array] = {}
# 相对路径 -> TreeItem，用于在创建子项时找到父节点
var _tree_items_by_path:Dictionary[String,TreeItem] = {}
# file_blacklist_editor 中的非空行，作为文件名通配符模式
var _file_blacklist_patterns:Array[String] = []
# global_blacklist_editor 中的非空行，作为全局变量名通配符模式
var _global_blacklist_patterns:Array[String] = []
# 当前选中的 lua 文件相对路径（SaveSingle 用）
var _current_file_rel:String = ""
# 黑名单去抖用的变更序号
var _file_blacklist_change_id := 0
var _global_blacklist_change_id := 0

@onready var file_tree: Tree = $HSplitContainer/LeftBar/VBoxContainer/VBoxContainer2/Tree
@onready var rbar_container: VBoxContainer = $HSplitContainer/RightBar/VSplitContainer/PanelContainer2/ScrollContainer/VBoxContainer
@onready var file_dialog: FileDialog = $FileDialog
@onready var file_blacklist_editor: CodeEdit = $HSplitContainer/LeftBar/VBoxContainer/VBoxContainer/FileBlacklistEditor
@onready var global_blacklist_editor: CodeEdit = $HSplitContainer/RightBar/VSplitContainer/PanelContainer/GlobalBlacklistEditor
@onready var pyramid_sprite: AnimatedSprite2D = $HSplitContainer/RightBar/VSplitContainer/PanelContainer2/Title/AnimatedSprite2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	file_tree.item_selected.connect(_on_tree_item_selected)
	file_blacklist_editor.text_changed.connect(_on_file_blacklist_text_changed)
	global_blacklist_editor.text_changed.connect(_on_global_blacklist_text_changed)
	await get_tree().process_frame
	if pyramid_sprite:
		pyramid_sprite.play("default")

func find_global_variable_accesses(lua_code: String) -> Array[String]:
	var global_vars: Array[String] = []
	var seen: Dictionary = {}

	var lua_ast = LuaParser.new().parse_code(lua_code)
	if lua_ast.has_errors():
		printerr("Lua 代码解析失败，存在语法错误")
		return global_vars

	# 作用域栈，栈底为 chunk 作用域
	var scope_stack: Array = [{}]
	_walk(lua_ast.root, scope_stack, global_vars, seen)
	return global_vars

func _walk(node: LuaASTNode, scope_stack: Array, global_vars: Array[String], seen: Dictionary) -> void:
	var t := node.get_type()

	var enter_scope := t in SCOPE_NODES
	if enter_scope:
		scope_stack.append({})

	# 进入作用域后，先把当前节点里的声明压入
	_register_declarations(node, scope_stack)

	match t:
		"identifier":
			_handle_identifier(node, scope_stack, global_vars, seen)

		"dot_index_expression", "method_index_expression":
			# a.b / a:b / a.b.c / a.b:c.d  ...
			# 只有第一个子节点是"被索引的对象"，才可能包含变量引用
			# 后面的 identifier 全部是字段名/方法名，剪枝跳过
			if node.get_child_count() > 0:
				_walk(node.get_child(0), scope_stack, global_vars, seen)

		"field":
			# 表构造器 field：`key = value` 形式时，key 不是变量引用
			var n := node.get_child_count()
			if n >= 2 \
			   and node.get_child(0).get_type() == "identifier" \
			   and node.get_child(1).get_type() == "=":
				for i in range(1, n):
					_walk(node.get_child(i), scope_stack, global_vars, seen)
			else:
				for i in range(n):
					_walk(node.get_child(i), scope_stack, global_vars, seen)

		"attribute":
			# <const> / <close> —— 里面的 identifier 是属性名
			pass

		"label_statement", "goto_statement":
			# goto / label 里的标识符不算变量
			pass

		_:
			for i in range(node.get_child_count()):
				_walk(node.get_child(i), scope_stack, global_vars, seen)

	if enter_scope:
		scope_stack.pop_back()


# ---------------------------------------------------------------
# 注册局部变量声明
# ---------------------------------------------------------------
func _register_declarations(node: LuaASTNode, scope_stack: Array) -> void:
	var t := node.get_type()
	var current: Dictionary = scope_stack.back()

	match t:
		"variable_declaration":
			# local a, b = 1, 2
			# variable_declaration -> assignment_statement -> variable_list -> identifier*
			for i in range(node.get_child_count()):
				var child := node.get_child(i)
				if child.get_type() == "assignment_statement":
					_register_variable_list(child, current)
					break

		"local_function_declaration":
			# local function foo() ... end
			for i in range(node.get_child_count()):
				var child := node.get_child(i)
				if child.get_type() == "identifier":
					current[child.get_source_code()] = true
					break

		"parameters":
			# 参数节点里的 identifier 全是变量名
			for i in range(node.get_child_count()):
				var child := node.get_child(i)
				if child.get_type() == "identifier":
					current[child.get_source_code()] = true

		"for_numeric_clause":
			# for i = 1, N do —— 第一个 identifier 是循环变量
			for i in range(node.get_child_count()):
				var child := node.get_child(i)
				if child.get_type() == "identifier":
					current[child.get_source_code()] = true
					break

		"for_generic_clause":
			# for k, v in pairs(t) do —— variable_list 里的 identifier 全是循环变量
			for i in range(node.get_child_count()):
				var child := node.get_child(i)
				if child.get_type() == "variable_list":
					for j in range(child.get_child_count()):
						var sub := child.get_child(j)
						if sub.get_type() == "identifier":
							current[sub.get_source_code()] = true
					break


func _register_variable_list(assignment: LuaASTNode, current: Dictionary) -> void:
	for i in range(assignment.get_child_count()):
		var child := assignment.get_child(i)
		if child.get_type() == "variable_list":
			for j in range(child.get_child_count()):
				var sub := child.get_child(j)
				if sub.get_type() == "identifier":
					current[sub.get_source_code()] = true
			return


# ---------------------------------------------------------------
# 判定 identifier 是否全局引用
# ---------------------------------------------------------------
func _handle_identifier(node: LuaASTNode, scope_stack: Array, global_vars: Array[String], seen: Dictionary) -> void:
	var name := node.get_source_code()

	# 关键字 / 隐式变量
	if name in ["self", "const", "nil", "true", "false"]:
		return

	# 逐层查找作用域
	for scope in scope_stack:
		if scope.has(name):
			return

	# 命中全局黑名单 → 不计入
	if _is_global_blacklisted(name):
		return

	# 未找到 → 全局变量
	if not seen.has(name):
		seen[name] = true
		global_vars.append(name)

## 该函数应当仅在测试时使用
func _dump(node: LuaASTNode, depth := 0, ostr:Array[String] = [""]) -> void:
	ostr[0]+="\n"+"  ".repeat(depth)+node.get_type()+ " : "+ node.get_source_code().substr(0, 60)
	for i in range(node.get_child_count()):
		_dump(node.get_child(i), depth + 1,ostr)
	if depth == 0:
		ast_dump_target.store_string(ostr[0])


# 选中目录后：清空旧结果，递归扫描所有 lua 文件并重建文件树
func _on_file_dialog_dir_selected(dir: String) -> void:
	_scan_root(dir)


# 清空旧结果并递归扫描 dir，重建整个文件树（root_path 也会更新为 dir）
func _scan_root(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		printerr("目录不存在: ", dir)
		return
	root_path = dir
	_current_file_rel = ""
	_refresh_file_blacklist()
	_refresh_global_blacklist()
	globals_find_result.clear()
	_tree_items_by_path.clear()
	file_tree.clear()
	# 根节点指向 root_path
	_create_tree_folder_item("")
	_scan_dir(dir, "")


# ---------------------------------------------------------------
# 黑名单
# ---------------------------------------------------------------
# 读取 CodeEdit 中每一非空行作为通配符模式（String.match）
func _read_blacklist_patterns(editor: CodeEdit) -> Array[String]:
	var patterns: Array[String] = []
	for line in editor.text.split("\n"):
		var pattern := line.strip_edges()
		if not pattern.is_empty():
			patterns.append(pattern)
	return patterns


func _refresh_file_blacklist() -> void:
	_file_blacklist_patterns = _read_blacklist_patterns(file_blacklist_editor)


func _refresh_global_blacklist() -> void:
	_global_blacklist_patterns = _read_blacklist_patterns(global_blacklist_editor)


# 文件名是否命中黑名单
func _is_file_blacklisted(name: String) -> bool:
	for pattern in _file_blacklist_patterns:
		if name.match(pattern):
			return true
	return false


# 全局变量名是否命中黑名单
func _is_global_blacklisted(name: String) -> bool:
	for pattern in _global_blacklist_patterns:
		if name.match(pattern):
			return true
	return false


# 文件黑名单文本变化（去抖）：文件增删 → 重建文件树
func _on_file_blacklist_text_changed() -> void:
	_file_blacklist_change_id += 1
	var change_id := _file_blacklist_change_id
	await get_tree().create_timer(TEXT_UPDATE_DEBOUNCE_TIME).timeout
	if change_id != _file_blacklist_change_id:
		return
	_rebuild_tree()


# 全局黑名单文本变化（去抖）：仅变量过滤 → 重新扫描全局变量，不重建树
func _on_global_blacklist_text_changed() -> void:
	_global_blacklist_change_id += 1
	var change_id := _global_blacklist_change_id
	await get_tree().create_timer(TEXT_UPDATE_DEBOUNCE_TIME).timeout
	if change_id != _global_blacklist_change_id:
		return
	_rescan_globals()


# 保持文件树不变，按当前全局黑名单重新分析已收录的文件
func _rescan_globals() -> void:
	if root_path.is_empty():
		return
	_refresh_global_blacklist()
	for rel_path in globals_find_result.keys():
		_analyze_file(root_path.path_join(rel_path), rel_path)
	if not _current_file_rel.is_empty() and globals_find_result.has(_current_file_rel):
		_on_tree_file_item_pressed(_current_file_rel)


# 递归遍历 dir_path，把 lua 文件存入 globals_find_result<relative_path, Array[found_globals_name]>，
# 并同步构建文件树
func _scan_dir(dir_path: String, rel_path: String) -> void:
	var diraccess := DirAccess.open(dir_path)
	if diraccess == null:
		printerr("无法打开目录: ", dir_path)
		return

	# 先建文件夹，保证子节点的父节点已存在
	var dirs: Array[String] = []
	for d in diraccess.get_directories():
		if not d.begins_with("."):
			dirs.append(d)
	dirs.sort()
	for d in dirs:
		if _is_file_blacklisted(d):
			continue
		var child_rel := d if rel_path.is_empty() else rel_path.path_join(d)
		_create_tree_folder_item(child_rel)
		_scan_dir(dir_path.path_join(d), child_rel)

	# 再处理 lua 文件
	var files: Array[String] = []
	for f in diraccess.get_files():
		if not f.begins_with(".") and f.get_extension().to_lower() == "lua":
			files.append(f)
	files.sort()
	for f in files:
		if _is_file_blacklisted(f):
			continue
		var child_rel := f if rel_path.is_empty() else rel_path.path_join(f)
		_create_tree_file_item(child_rel)
		_analyze_file(dir_path.path_join(f), child_rel)


# 读取单个 lua 文件并分析其全局变量引用
func _analyze_file(file_path: String, rel_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		printerr("无法读取文件: ", file_path, " (", FileAccess.get_open_error(), ")")
		return
	var lua_code := file.get_as_text()
	file.close()
	globals_find_result[rel_path] = find_global_variable_accesses(lua_code)


func _on_open_button_pressed() -> void:
	if file_dialog:
		file_dialog.show()

# path为指向与rootpath相对路径上的文件夹（""表示root_path本身），返回创建的TreeItem
func _create_tree_folder_item(path:String) -> TreeItem:
	if root_path.is_empty():
		return null
	var parent_item: TreeItem = _tree_items_by_path.get(_parent_rel_path(path))
	var item := file_tree.create_item(parent_item)
	item.set_text(0, root_path.get_file() if path.is_empty() else path.get_file())
	item.set_icon(0, FOLDER_ICON)
	item.set_icon_max_width(0, TREE_ICON_MAX_WIDTH)
	_tree_items_by_path[path] = item
	return item

# path为指向与rootpath相对路径上的文件，返回创建的TreeItem
func _create_tree_file_item(path:String) -> TreeItem:
	if root_path.is_empty():
		return null
	var parent_item: TreeItem = _tree_items_by_path.get(_parent_rel_path(path))
	var item := file_tree.create_item(parent_item)
	item.set_text(0, path.get_file())
	item.set_icon(0, FILE_ICON)
	item.set_icon_max_width(0, TREE_ICON_MAX_WIDTH)
	# 记录相对路径，点击时据此取回分析结果
	item.set_metadata(0, path)
	return item


# 取相对路径的父目录（顶层的父目录为根节点 ""）
func _parent_rel_path(path: String) -> String:
	if path.is_empty():
		return ""
	var base := path.get_base_dir()
	return "" if base == "." else base


# 文件树项被按下：取回对应的相对路径并展示
func _on_tree_item_selected() -> void:
	var item := file_tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is String and globals_find_result.has(meta):
		_current_file_rel = meta
		_on_tree_file_item_pressed(meta)


# 按下后清空rbar_container原有元素，然后将当前文件的globals用数个label在rbar_container中展示
func _on_tree_file_item_pressed(path: String) -> void:
	for child in rbar_container.get_children():
		child.queue_free()
	var globals: Array = globals_find_result.get(path, [])
	for g in globals:
		var label := Label.new()
		label.text = str(g)
		rbar_container.add_child(label)

# 在当前 lua 文件头部用 `local g = g` 缓存扫描到的全局变量（globals_find_result 已排除黑名单），
# 等待一帧后重建文件树，并按当前文件重新扫描全局变量
func _on_save_single_pressed() -> void:
	if _current_file_rel.is_empty() or not globals_find_result.has(_current_file_rel):
		return
	var saved_rel := _current_file_rel
	_cache_globals_to_file(saved_rel)
	await get_tree().process_frame
	_rebuild_tree()
	# 重建后 _current_file_rel 被清空，恢复选中文件并重新扫描以刷新展示
	_current_file_rel = saved_rel
	_rescan_globals()


# 在所有未被黑名单排除的文件头部缓存全局变量，等待一帧后重建文件树，并按当前文件重新扫描全局变量
func _on_save_all_pressed() -> void:
	var saved_rel := _current_file_rel
	for rel_path in globals_find_result.keys():
		_cache_globals_to_file(rel_path)
	await get_tree().process_frame
	_rebuild_tree()
	# 重建后 _current_file_rel 被清空，恢复选中文件并重新扫描以刷新展示
	_current_file_rel = saved_rel
	_rescan_globals()


# 把扫描到的全局变量以 `local g = g` 形式写入指定 lua 文件头部
func _cache_globals_to_file(rel_path: String) -> void:
	var globals: Array = globals_find_result.get(rel_path, [])
	if globals.is_empty():
		return
	var abs_path := root_path.path_join(rel_path)
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		printerr("无法读取文件: ", abs_path, " (", FileAccess.get_open_error(), ")")
		return
	var content := file.get_as_text()
	file.close()

	var cache_block := ""
	for g in globals:
		cache_block += "local %s = %s\n" % [g, g]

	var out := FileAccess.open(abs_path, FileAccess.WRITE)
	if out == null:
		printerr("无法写入文件: ", abs_path, " (", FileAccess.get_open_error(), ")")
		return
	out.store_string(cache_block + content)
	out.close()


# 重新扫描 root_path 并重建文件树
func _rebuild_tree() -> void:
	if root_path.is_empty():
		return
	_scan_root(root_path)
