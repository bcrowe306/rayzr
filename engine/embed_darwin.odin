#+build darwin
package engine

import NS "core:sys/darwin/Foundation"

// Embed_KeepAwake: a hidden game is never visible, so macOS would nap it
// (slow timers, a few frames a second): tell it the user is waiting on it.
Embed_KeepAwake :: proc() {
	// NSActivityUserInitiatedAllowingIdleSystemSleep | NSActivityLatencyCritical
	// (the binding's option bits are single bits; these are masks).
	opts := transmute(NS.ActivityOptions)u64(0x00EF_FFFF | 0xFF_0000_0000)
	_ = NS.ProcessInfo_processInfo()->beginActivityWithOptions(opts, NS.AT("Rayzr Game view"))
}
