extends Node
## Сигналы между логикой и интерфейсом.

signal state_changed
signal event_opened(event_id: String)
signal draft_changed(event_id: String)
signal option_resolved(result: Dictionary)
signal initiator_used(event_id: String)
signal toast(text: String)
