package app

import sdtx "libs:sdtx"
import sg "libs:sg"

FONT_KC853 :: 0
FONT_KC854 :: 1
FONT_Z1013 :: 2
FONT_CPC :: 3
FONT_C64 :: 4
FONT_ORIC :: 5

debugtext_state :: struct {
    pass_action: sg.Pass_Action,
}
sdtx_s: debugtext_state

debugtext_init :: proc() {
    sdtx.setup(&sdtx.Desc{
        fonts = {
            FONT_KC853 = sdtx.font_kc853(),
            FONT_KC854 = sdtx.font_kc854(),
            FONT_Z1013 = sdtx.font_z1013(),
            FONT_CPC = sdtx.font_cpc(),
            FONT_C64 = sdtx.font_c64(),
            FONT_ORIC = sdtx.font_oric(),
        },
    })
    sdtx_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0.0, 0.125, 0.25, 1.0}}}}
}

debugtext_print_font :: proc(font_index: u32, title: cstring, r, g, b: u8) {
    sdtx.font(font_index)
    sdtx.color3b(r, g, b)
    sdtx.puts(title)
    for c in 32..<256 {
        sdtx.putc(u8(c))
        if ((c + 1) & 63) == 0 {
            sdtx.crlf()
        }
    }
    sdtx.crlf()
}

debugtext_frame :: proc(w, h: i32) {
    sdtx.canvas(f32(w) * 0.5, f32(h) * 0.5)
    sdtx.origin(0.0, 2.0)
    sdtx.home()
    debugtext_print_font(FONT_KC853, "KC85/3:\n", 0xf4, 0x43, 0x36)
    debugtext_print_font(FONT_KC854, "KC85/4:\n", 0x21, 0x96, 0xf3)
    debugtext_print_font(FONT_Z1013, "Z1013:\n", 0x4c, 0xaf, 0x50)
    debugtext_print_font(FONT_CPC, "Amstrad CPC:\n", 0xff, 0xeb, 0x3b)
    debugtext_print_font(FONT_C64, "C64:\n", 0x79, 0x86, 0xcb)
    debugtext_print_font(FONT_ORIC, "Oric Atmos:\n", 0xff, 0x98, 0x00)
    sample_begin_pass(&sdtx_s.pass_action, w, h)
    sdtx.draw()
    sg.end_pass()
    sg.commit()
}

debugtext_shutdown :: proc() {
    sdtx.shutdown()
}
