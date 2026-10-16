//! Win32 ABI declarations and explicit current-token-user security descriptor.
const std = @import("std");
const w = std.os.windows;
const WINAPI = std.builtin.CallingConvention.winapi;
const BOOL = i32;
pub const PIPE_ACCESS_DUPLEX = 0x00000003;
pub const FILE_FLAG_FIRST_PIPE_INSTANCE = 0x00080000;
pub const PIPE_REJECT_REMOTE_CLIENTS = 0x00000008;
const Attributes = extern struct {
    length: u32 = @sizeOf(Attributes),
    descriptor: ?*anyopaque,
    inherit: BOOL = 0,
};
pub extern "kernel32" fn CreateNamedPipeW([*:0]const u16, u32, u32, u32, u32, u32, u32, *const Attributes) callconv(WINAPI) w.HANDLE;
pub extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const Attributes, u32, u32, ?w.HANDLE) callconv(WINAPI) w.HANDLE;
pub extern "kernel32" fn ConnectNamedPipe(w.HANDLE, ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn DisconnectNamedPipe(w.HANDLE) callconv(WINAPI) BOOL;
pub extern "kernel32" fn ReadFile(w.HANDLE, [*]u8, u32, *u32, ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn WriteFile(w.HANDLE, [*]const u8, u32, *u32, ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn CloseHandle(w.HANDLE) callconv(WINAPI) BOOL;
pub extern "kernel32" fn GetLastError() callconv(WINAPI) u32;
pub extern "kernel32" fn GetCurrentProcessId() callconv(WINAPI) u32;
extern "kernel32" fn GetCurrentProcess() callconv(WINAPI) w.HANDLE;
extern "kernel32" fn LocalFree(?*anyopaque) callconv(WINAPI) ?*anyopaque;
extern "advapi32" fn OpenProcessToken(w.HANDLE, u32, *w.HANDLE) callconv(WINAPI) BOOL;
extern "advapi32" fn GetTokenInformation(w.HANDLE, u32, ?*anyopaque, u32, *u32) callconv(WINAPI) BOOL;
extern "advapi32" fn ConvertSidToStringSidW(*anyopaque, *?[*:0]u16) callconv(WINAPI) BOOL;
extern "advapi32" fn ConvertStringSecurityDescriptorToSecurityDescriptorW([*:0]const u16, u32, *?*anyopaque, ?*u32) callconv(WINAPI) BOOL;

pub const Security = struct {
    attributes: Attributes,
    pub fn init(alloc: std.mem.Allocator) !Security {
        var token: w.HANDLE = undefined;
        if (OpenProcessToken(GetCurrentProcess(), 0x0008, &token) == 0) return error.TokenOpenFailed;
        defer _ = CloseHandle(token);
        var size: u32 = 0;
        _ = GetTokenInformation(token, 1, null, 0, &size);
        if (size == 0 or GetLastError() != 122) return error.TokenQueryFailed;
        const info = try alloc.alignedAlloc(u8, .of(usize), size);
        defer alloc.free(info);
        if (GetTokenInformation(token, 1, info.ptr, size, &size) == 0) return error.TokenQueryFailed;
        // TOKEN_USER starts with SID_AND_ATTRIBUTES, whose first field is PSID.
        const sid: *const *anyopaque = @ptrCast(@alignCast(info.ptr));
        var sid_text: ?[*:0]u16 = null;
        if (ConvertSidToStringSidW(sid.*, &sid_text) == 0) return error.SidConversionFailed;
        defer _ = LocalFree(@ptrCast(sid_text.?));
        const text = try std.unicode.utf16LeToUtf8Alloc(alloc, std.mem.span(sid_text.?));
        defer alloc.free(text);
        // Protected DACL with exactly one trustee: the process token's user SID.
        // Do not use OW: an elevated token can assign Administrators as owner.
        const sddl = try std.fmt.allocPrint(alloc, "D:P(A;;GA;;;{s})", .{text});
        defer alloc.free(sddl);
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(alloc, sddl);
        defer alloc.free(wide);
        var descriptor: ?*anyopaque = null;
        if (ConvertStringSecurityDescriptorToSecurityDescriptorW(wide, 1, &descriptor, null) == 0)
            return error.SecurityDescriptorFailed;
        return .{ .attributes = .{ .descriptor = descriptor } };
    }
    pub fn deinit(self: *Security) void {
        _ = LocalFree(self.attributes.descriptor);
        self.* = undefined;
    }
};
pub extern "kernel32" fn FlushFileBuffers(w.HANDLE) callconv(WINAPI) BOOL;

extern "advapi32" fn DuplicateToken(w.HANDLE, u32, *w.HANDLE) callconv(WINAPI) BOOL;
extern "advapi32" fn CreateRestrictedToken(w.HANDLE, u32, u32, ?*anyopaque, u32, ?*anyopaque, u32, *const SidAttributes, *w.HANDLE) callconv(WINAPI) BOOL;
extern "advapi32" fn CreateWellKnownSid(u32, ?*anyopaque, *anyopaque, *u32) callconv(WINAPI) BOOL;
extern "advapi32" fn SetThreadToken(?*w.HANDLE, ?w.HANDLE) callconv(WINAPI) BOOL;
extern "advapi32" fn RevertToSelf() callconv(WINAPI) BOOL;
const SidAttributes = extern struct { sid: *anyopaque, attributes: u32 = 0 };

/// Test negative control: same identity, restricted to the World SID for the
/// additional restricted-token access check. This must not satisfy our user ACE.
/// This is not a substitute for a real second-user integration run.
pub fn expectRestrictedClientDenied(name: [*:0]const u16) !void {
    var token: w.HANDLE = undefined;
    if (OpenProcessToken(GetCurrentProcess(), 0x000e, &token) == 0) return error.TokenOpenFailed;
    defer _ = CloseHandle(token);
    var sid: [68]u8 align(@alignOf(usize)) = undefined;
    var size: u32 = sid.len;
    if (CreateWellKnownSid(1, null, &sid, &size) == 0) return error.SidCreationFailed;
    const restricting = SidAttributes{ .sid = &sid };
    var restricted: w.HANDLE = undefined;
    if (CreateRestrictedToken(token, 0, 0, null, 0, null, 1, &restricting, &restricted) == 0)
        return error.TokenRestrictionFailed;
    defer _ = CloseHandle(restricted);
    var impersonation: w.HANDLE = undefined;
    if (DuplicateToken(restricted, 2, &impersonation) == 0) return error.TokenDuplicateFailed;
    defer _ = CloseHandle(impersonation);
    if (SetThreadToken(null, impersonation) == 0) return error.ImpersonationFailed;
    // Always restore the thread, including on test failures.
    defer if (RevertToSelf() == 0) @panic("failed to restore test thread token");
    const handle = CreateFileW(name, 0xC0000000, 0, null, 3, 0, null);
    if (handle != w.INVALID_HANDLE_VALUE) {
        _ = CloseHandle(handle);
        return error.RestrictedClientUnexpectedlyAllowed;
    }
    if (GetLastError() != 5) return error.ExpectedAccessDenied;
}
