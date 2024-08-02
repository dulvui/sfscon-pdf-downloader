# SPDX-FileCopyrightText: (c) NOI Techpark <digital@noi.bz.it>

# SPDX-License-Identifier: AGPL-3.0-or-later

extends Control

# column keys are case-insensitive
const ID_KEY: String = "id"
const DATE_KEY: String = "date"
const TIME_KEY: String = "time" 
const TITLE_KEY: String = "title"
const ROOM_KEY: String = "room"
const TRACK_KEY: String = "tracks"
const STATUS_KEY: String = "status"
const SPEAKER_KEY: String = "speakers"
const PDF_LINK_KEY: String = "pdf presentation"

var keys_index: Dictionary = {
	ID_KEY: -1,
	DATE_KEY: -1,
	TIME_KEY: -1,
	TITLE_KEY: -1,
	ROOM_KEY: -1,
	TRACK_KEY: -1,
	STATUS_KEY: -1,
	SPEAKER_KEY: -1,
	PDF_LINK_KEY: -1,
}

# TODO make day mapping input field
const DAY_MAPPING: Dictionary = { 
	"10/11/2024" : "Day 1",
	"11/11/2024" : "Day 2",
}

@onready var file_dialog: FileDialog = $WebsiteFileDialog

@onready var progress_label: Label = $Result/ProgressLabel
@onready var statistics_label: Label = $Result/Statistics
@onready var progress_bar: ProgressBar = $Result/ProgressBar
@onready var http: HTTPRequest = $HTTPRequest
@onready var result: VBoxContainer = $Result

@onready var errors: RichTextLabel = $Result/Errors
@onready var errors2: RichTextLabel = $Result/Errors2

@onready var settings: VBoxContainer = $Settings
@onready var example: Label = $Settings/Example

@onready var time_checkbox: CheckBox = $Settings/HBoxContainer/TimeCheckbox
@onready var title_checkbox: CheckBox = $Settings/HBoxContainer/TitleCheckBox
@onready var regex_checkbox: CheckBox = $Settings/HBoxContainer/RegexCheckbox

var pdf_path: String

# stores the csv combined data
var data: Dictionary = {}
var counter_done: int = 0
var counter_pdf: int = 0
var counter_total: int = 0

var config: ConfigFile

var regex: RegEx = RegEx.new()

var include_title: bool
var include_time: bool
var include_special_characters: bool

func _ready() -> void:
	regex.compile("\\w+")

	_load_config()
	
	time_checkbox.button_pressed = include_time
	title_checkbox.button_pressed = include_title
	regex_checkbox.button_pressed = include_special_characters
	
	if not pdf_path.is_empty():
		file_dialog.current_path = pdf_path
	
	_update_example()


func _load_config() -> void:
	config = ConfigFile.new()
	config.load("user://settings.cfg")
	pdf_path = config.get_value("settings", "pdf_path", "")
	include_title = config.get_value("settings", "include_title", true)
	include_time = config.get_value("settings", "include_time", true)
	include_special_characters = config.get_value("settings", "include_special_characters", true)


func _save_config(path: String) -> void:
	pdf_path = path + "/"
	config.set_value("settings", "pdf_path", pdf_path)
	config.set_value("settings", "include_title", include_title)
	config.set_value("settings", "include_time", include_time)
	config.set_value("settings", "include_special_characters", include_special_characters)
	config.save("user://settings.cfg")


func _process(delta) -> void:
	if counter_done < counter_pdf:
		progress_label.text = "Downloading %d of %d..."%[counter_done, counter_pdf]
	elif counter_pdf == 0:
		progress_label.text = "Something went wrong, restart please"
	else:
		progress_label.text = "Finished! Happy SFSCON :-)"
	progress_bar.value = counter_done


func _on_submit_pressed():
	settings.hide()
	file_dialog.show()


func _on_website_file_dialog_file_selected(path: String) -> void:
	_save_config(path.get_base_dir())
	
	var file:FileAccess = FileAccess.open(path, FileAccess.READ)
	
	# search for key index values on header row
	var header: PackedStringArray = file.get_csv_line()
	
	for key: String in keys_index.keys():
		keys_index[key] = header.find(key)
	
	
	
	while not file.eof_reached():
		var line: Array = file.get_csv_line()
		if line.size() > 1:
			var id: String = line[keys_index[ID_KEY]]
			if _is_approved(line):
				var pdf_link: String = line[keys_index[PDF_LINK_KEY]]
				var title: String = line[keys_index[TITLE_KEY]]
				
				var date: String = line[keys_index[DATE_KEY]]
				counter_total += 1
				if not data.has(id):
					errors.append_text(str(errors.get_line_count()) + ") " + title + "\n")
				elif pdf_link.begins_with("https://www.sfscon.it/wp-content/uploads/"):
					data[id]["pdf_link"] = pdf_link
					data[id]["speaker"] = _escape_string(keys_index[SPEAKER_KEY])
					data[id]["time"] = keys_index[TIME_KEY].substr(0,5).replace(":", "")
					data[id]["day"] = _get_day(date)
					counter_pdf += 1
			else:
				data.erase(id)
				print("not approved ", keys_index[TITLE_KEY])
	progress_bar.max_value = counter_pdf
	statistics_label.text = "Total: %d  -  Pdf: %d  -  No Pdf: %d"%[counter_total, counter_pdf, counter_total - counter_pdf]
	_download_pdfs()
	
	result.show()


func _download_pdfs() -> void:
	for id in data.keys():
		if data[id].has("pdf_link") and data[id]["pdf_link"].begins_with("https://www.sfscon.it/wp-content/uploads/"):
			if http.request_completed.is_connected(_request_completed):
				http.request_completed.disconnect(_request_completed)
			http.request_completed.connect(_request_completed.bind(data[id]))
			var error = http.request(data[id]["pdf_link"])
			if error != OK:
				print(error)
			await http.request_completed
		else:
			errors.append_text(str(errors.get_line_count()) + ") " + data[id]["title"] + "\n")


func _request_completed(result, response_code, headers, body:PackedByteArray, talk:Dictionary) -> void:
	if talk["track"].length() == 0:
		print("Talk with no room assigned: \n" + talk["title"])
		counter_done += 1
		return
	
	var dir_name: String = talk["day"]  + " - " + talk["room"] + " - " + talk["track"]
	var base_path: String = _prepare_dir(pdf_path, dir_name)
	
	var file_name: String = _format_file_name(talk["time"], talk["title"], talk["speaker"])
	
	var file_path: String = "%s/%s"%[base_path, file_name]
	# remove new lines, double points and tabs
	file_path = file_path.replace("..",".")
	print(file_path)
	var file:FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_buffer(body)
	file.flush()
	
	if not FileAccess.file_exists(file_path):
		errors2.append_text(str(errors2.get_line_count()) + ") " + file_path + "\n")
	counter_done += 1
	
func _prepare_dir(base_path: String, path: String) -> String:
	var dir = DirAccess.open(base_path)
	if not dir.dir_exists(base_path + path):
		dir.make_dir(base_path + path)
	dir.change_dir(base_path + path)
	return base_path + path

func _get_day(day: String) -> String:
	if DAY_MAPPING.has(day):
		return DAY_MAPPING[day]
	return "TBD"
	
func _escape_string(string: String) -> String:
	var results: Array[RegExMatch] = regex.search_all(string)
	var escaped = "";
	
	# remove non alphanumerical characters
	if results:
		for result in results:
			escaped += " " + result.get_string()
	return escaped


func _on_restart_pressed():
	get_tree().change_scene_to_file("res://src/Main.tscn")

func _is_approved(line: Array) -> bool:
	var date: String = line[keys_index[DATE_KEY]]
	var time: String = line[keys_index[TIME_KEY]]
	if date == "✗":
		return false
	if time == "✗":
		return false
	return true


func _on_time_checkbox_toggled(button_pressed):
	include_time = button_pressed
	_update_example()


func _on_title_check_box_toggled(button_pressed):
	include_title = button_pressed
	_update_example()


func _on_regex_checkbox_toggled(button_pressed):
	include_special_characters = button_pressed
	_update_example()


func _update_example() -> void:
	var time: String = "1030"
	var title: String = "Talk about $$$"
	var speaker: String = "Märio Rössi"
	
	example.text = _format_file_name(time, title, speaker)
	
func _format_file_name(time: String, title: String, speaker: String) -> String:
	if not include_time:
		time = ""
	if not include_title:
		title = ""
		
	if not include_special_characters:
		title = _escape_string(title)
		speaker = _escape_string(speaker)
	
	var text: String = ""
	if include_time:
		text = time + " - "
	text += speaker
	if include_title:
		text  += " - " + title
	text += ".pdf"
	
	# other escapes
	text = text.replace("/"," ")
	text = text.strip_escapes()
	text = text.strip_edges()
	
	return text
