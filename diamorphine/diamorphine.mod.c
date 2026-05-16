#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};



static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0x5a844b26, "__x86_indirect_thunk_rax" },
	{ 0xbd03ed67, "__ref_stack_chk_guard" },
	{ 0x1c489eb6, "register_kprobe" },
	{ 0x7a8e92c6, "unregister_kprobe" },
	{ 0xd272d446, "__stack_chk_fail" },
	{ 0xd710adbf, "__kmalloc_noprof" },
	{ 0x546c19d9, "validate_usercopy_range" },
	{ 0xa61fd7aa, "__check_object_size" },
	{ 0x092a35a2, "_copy_from_user" },
	{ 0x2435d559, "strncmp" },
	{ 0xe54e0a6b, "__fortify_panic" },
	{ 0xcb8b6ec6, "kfree" },
	{ 0x092a35a2, "_copy_to_user" },
	{ 0xa53f4e29, "memmove" },
	{ 0x2719b9fa, "const_current_task" },
	{ 0xd272d446, "__fentry__" },
	{ 0xd272d446, "__x86_return_thunk" },
	{ 0xe8213e80, "_printk" },
	{ 0xbebe66ff, "module_layout" },
};

static const u32 ____version_ext_crcs[]
__used __section("__version_ext_crcs") = {
	0x5a844b26,
	0xbd03ed67,
	0x1c489eb6,
	0x7a8e92c6,
	0xd272d446,
	0xd710adbf,
	0x546c19d9,
	0xa61fd7aa,
	0x092a35a2,
	0x2435d559,
	0xe54e0a6b,
	0xcb8b6ec6,
	0x092a35a2,
	0xa53f4e29,
	0x2719b9fa,
	0xd272d446,
	0xd272d446,
	0xe8213e80,
	0xbebe66ff,
};
static const char ____version_ext_names[]
__used __section("__version_ext_names") =
	"__x86_indirect_thunk_rax\0"
	"__ref_stack_chk_guard\0"
	"register_kprobe\0"
	"unregister_kprobe\0"
	"__stack_chk_fail\0"
	"__kmalloc_noprof\0"
	"validate_usercopy_range\0"
	"__check_object_size\0"
	"_copy_from_user\0"
	"strncmp\0"
	"__fortify_panic\0"
	"kfree\0"
	"_copy_to_user\0"
	"memmove\0"
	"const_current_task\0"
	"__fentry__\0"
	"__x86_return_thunk\0"
	"_printk\0"
	"module_layout\0"
;

MODULE_INFO(depends, "");


MODULE_INFO(srcversion, "81D2EDFDB8B452355EE85A8");
