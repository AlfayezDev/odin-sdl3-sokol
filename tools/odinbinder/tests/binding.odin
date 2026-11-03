package binding

Color :: enum i32 {
	Red = 5,
	Green = 6,
	Blue = 7,
	object = 8,
	default = 9,
	Neg = -1,
}

Mode :: enum u32 {
	Max = 4294967295,
}

Nullable_CString :: cstring

@(odinbinder={
	name = "bridge",
	android_package = "dev.example",
	android_class = "Bridge",
	ios_module = "Bridge",
})
_config :: struct {}

@(odinbinder={direction="import", thread="ui"})
pick_color :: proc "c" (current: Color) -> Color

@(odinbinder={direction="import", thread="ui"})
show_message :: proc "c" (msg: Nullable_CString)

@(odinbinder={direction="import"})
object :: proc "c" ()

@(odinbinder={direction="export"})
default :: proc "c" ()

@(odinbinder={direction="export"})
set_color :: proc "c" (color: Color)

@(odinbinder={direction="export"})
current_color :: proc "c" () -> Color
