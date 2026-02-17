extends Control

@onready var campaign_option: OptionButton = $Center/Panel/Margin/VBox/SelectionRow/CampaignCol/CampaignOption
@onready var route_option: OptionButton = $Center/Panel/Margin/VBox/SelectionRow/RouteCol/RouteOption
@onready var info_label: Label = $Center/Panel/Margin/VBox/InfoLabel
@onready var start_button: Button = $Center/Panel/Margin/VBox/ButtonsRow/StartButton
@onready var quit_button: Button = $Center/Panel/Margin/VBox/ButtonsRow/QuitButton

var _campaign_ids: Array[StringName] = []


func _ready() -> void:
	if GameManager:
		GameManager.resume_game()

	if StageManager and StageManager.has_method("stop_gameplay"):
		StageManager.stop_gameplay()

	_populate_routes()
	_populate_campaigns()

	if campaign_option:
		campaign_option.item_selected.connect(_on_campaign_selected)
	if route_option:
		route_option.item_selected.connect(_on_route_selected)
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	_select_initial_defaults()
	_refresh_availability()

	if start_button and not start_button.disabled:
		start_button.grab_focus()
	elif campaign_option:
		campaign_option.grab_focus()


func _populate_routes() -> void:
	if not route_option:
		return
	route_option.clear()
	route_option.add_item("Base", int(StageManager.Route.BASE))
	route_option.add_item("Extra", int(StageManager.Route.EXTRA))
	route_option.select(0)


func _populate_campaigns() -> void:
	_campaign_ids = []
	if not campaign_option:
		return
	campaign_option.clear()

	var defs: Array[Dictionary] = []
	if StageManager and StageManager.has_method("get_campaign_defs"):
		defs = StageManager.get_campaign_defs()

	for d in defs:
		var id: StringName = d.get("id", &"")
		var title: String = str(d.get("title", ""))
		var base_open: bool = bool(d.get("base_open", false))
		var suffix := "" if base_open else "（预留）"
		campaign_option.add_item("%s%s" % [title, suffix])
		_campaign_ids.append(id)

	if _campaign_ids.is_empty():
		campaign_option.add_item("黄豆风神录")
		_campaign_ids.append(&"fushinroku")


func _select_initial_defaults() -> void:
	if not campaign_option:
		return

	var desired: StringName = &"fushinroku"
	if StageManager and ("current_campaign_id" in StageManager):
		desired = StageManager.current_campaign_id

	var idx := _campaign_ids.find(desired)
	if idx < 0:
		idx = 0
	campaign_option.select(idx)

	if route_option:
		route_option.select(0)


func _get_selected_campaign_id() -> StringName:
	if _campaign_ids.is_empty() or not campaign_option:
		return &"fushinroku"
	var idx := clampi(int(campaign_option.get_selected()), 0, _campaign_ids.size() - 1)
	return _campaign_ids[idx]


func _get_selected_route() -> int:
	if not route_option:
		return int(StageManager.Route.BASE)
	return int(route_option.get_selected_id())


func _refresh_availability() -> void:
	var campaign_id := _get_selected_campaign_id()
	var base_open := false
	var extra_open := false
	if StageManager and StageManager.has_method("is_route_available"):
		base_open = StageManager.is_route_available(campaign_id, int(StageManager.Route.BASE))
		extra_open = StageManager.is_route_available(campaign_id, int(StageManager.Route.EXTRA))

	if route_option:
		route_option.set_item_disabled(0, not base_open)
		route_option.set_item_disabled(1, not extra_open)

		# If the current selection is disabled, snap to the first available route.
		var sel := int(route_option.get_selected())
		if route_option.is_item_disabled(sel):
			if base_open:
				route_option.select(0)
			elif extra_open:
				route_option.select(1)

	var route := _get_selected_route()
	var can_start := false
	if StageManager and StageManager.has_method("is_route_available"):
		can_start = StageManager.is_route_available(campaign_id, route)

	if start_button:
		start_button.disabled = not can_start

	if info_label:
		var campaign_title := ""
		if StageManager and StageManager.has_method("get_campaign_title"):
			campaign_title = StageManager.get_campaign_title(campaign_id)
		if campaign_title == "":
			campaign_title = str(campaign_id)

		if can_start:
			info_label.text = "已选择：%s %s" % [campaign_title, StageManager.get_route_label(route)]
		else:
			if base_open or extra_open:
				info_label.text = "该路线暂未开放"
			else:
				info_label.text = "该关卡暂未开放（预留）"


func _on_campaign_selected(_idx: int) -> void:
	_refresh_availability()


func _on_route_selected(_idx: int) -> void:
	_refresh_availability()


func _on_start_pressed() -> void:
	var campaign_id := _get_selected_campaign_id()
	var route := _get_selected_route()
	if StageManager and StageManager.has_method("is_route_available"):
		if not StageManager.is_route_available(campaign_id, route):
			_refresh_availability()
			return

	if GameManager:
		GameManager.reset_run_state()

	if StageManager and StageManager.has_method("begin_run"):
		StageManager.begin_run(campaign_id, route)

	get_tree().change_scene_to_file("res://scenes/world/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

