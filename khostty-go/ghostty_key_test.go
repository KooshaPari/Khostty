package khostty

import "testing"

// Tests for the generated key table, key event state, and encoder reuse.

// TestKeyAndModsString checks the symbolic names used in failures and logs.
func TestKeyAndModsString(t *testing.T) {
	if got := KeyC.String(); got != "C" {
		t.Errorf("KeyC.String() = %q, want %q", got, "C")
	}
	if got := KeyArrowUp.String(); got != "ARROW_UP" {
		t.Errorf("KeyArrowUp.String() = %q, want %q", got, "ARROW_UP")
	}
	if got := Key(99999).String(); got == "" {
		t.Error("an unnamed key should still render something")
	}
	if got := (ModCtrl | ModAlt).String(); got != "mods{ctrl,alt}" {
		t.Errorf("mods string = %q, want %q", got, "mods{ctrl,alt}")
	}
	if got := Mods(0).String(); got != "mods{}" {
		t.Errorf("empty mods string = %q, want %q", got, "mods{}")
	}

	if !(ModCtrl | ModAlt).Has(ModCtrl) {
		t.Error("Has(ModCtrl) should be true when both ctrl and alt are held")
	}
	if (ModCtrl | ModAlt).Has(ModShift) {
		t.Error("Has(ModShift) should be false")
	}
}

// TestGeneratedKeysMatchManifest re-derives every generated key constant from
// the library's own manifest.
//
// keys_gen.go is produced by tools/genkeys. Without this check a stale table
// would silently select the wrong key rather than failing.
func TestGeneratedKeysMatchManifest(t *testing.T) {
	m, err := ParseManifest(TypeManifest())
	if err != nil {
		t.Fatalf("ParseManifest: %v", err)
	}
	values, ok := m.EnumValues("GhosttyKey")
	if !ok {
		t.Fatal("manifest has no GhosttyKey enum")
	}

	if len(keyNames) != len(values)-1 { // the MAX_VALUE sentinel is not a key
		t.Errorf("generated %d key names, manifest has %d real members",
			len(keyNames), len(values)-1)
	}

	seen := make(map[Key]string, len(keyNames))
	for key, name := range keyNames {
		want, ok := values[name]
		if !ok {
			t.Errorf("generated key %s is not in the manifest", name)
			continue
		}
		if int(key) != want {
			t.Errorf("key %s = %d, manifest says %d", name, int(key), want)
		}
		if other, dup := seen[key]; dup {
			t.Errorf("keys %s and %s share value %d", other, name, int(key))
		}
		seen[key] = name
	}

	for name, val := range values {
		if name == "MAX_VALUE" {
			continue
		}
		if got, ok := seen[Key(val)]; !ok || got != name {
			t.Errorf("manifest member %s = %d is missing from the generated table", name, val)
		}
	}
}

// TestEncodeControlKeys covers the keys that encode without any text.
func TestEncodeControlKeys(t *testing.T) {
	cases := []struct {
		name   string
		key    Key
		mods   Mods
		action KeyAction
		want   string
	}{
		{"enter", KeyEnter, 0, KeyPress, "\r"},
		{"escape", KeyEscape, 0, KeyPress, "\x1b"},
		{"tab", KeyTab, 0, KeyPress, "\t"},
		{"backspace", KeyBackspace, 0, KeyPress, "\x7f"},
		{"ctrl-c", KeyC, ModCtrl, KeyPress, "\x03"},
		{"ctrl-d", KeyD, ModCtrl, KeyPress, "\x04"},
		{"arrow-up", KeyArrowUp, 0, KeyPress, "\x1b[A"},
		{"arrow-down", KeyArrowDown, 0, KeyPress, "\x1b[B"},
		{"arrow-right", KeyArrowRight, 0, KeyPress, "\x1b[C"},
		{"arrow-left", KeyArrowLeft, 0, KeyPress, "\x1b[D"},
		{"home", KeyHome, 0, KeyPress, "\x1b[H"},
		{"delete", KeyDelete, 0, KeyPress, "\x1b[3~"},
		{"f1", KeyF1, 0, KeyPress, "\x1bOP"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := EncodeKey(tc.key, tc.mods, tc.action)
			if err != nil {
				t.Fatalf("EncodeKey: %v", err)
			}
			if string(got) != tc.want {
				t.Errorf("EncodeKey(%s, %s) = %q, want %q", tc.key, tc.mods, got, tc.want)
			}
		})
	}
}

// TestKeyEventStateRoundTrip covers the setters and getters.
func TestKeyEventStateRoundTrip(t *testing.T) {
	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetKey(KeyF5); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetMods(ModShift | ModCtrl); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetConsumedMods(ModShift); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetAction(KeyRepeat); err != nil {
		t.Fatal(err)
	}
	if err := ev.SetComposing(true); err != nil {
		t.Fatal(err)
	}

	if got, err := ev.Key(); err != nil || got != KeyF5 {
		t.Errorf("Key() = %v (err %v), want KeyF5", got, err)
	}
	if got, err := ev.Mods(); err != nil || got != ModShift|ModCtrl {
		t.Errorf("Mods() = %v (err %v), want shift|ctrl", got, err)
	}
	if got, err := ev.ConsumedMods(); err != nil || got != ModShift {
		t.Errorf("ConsumedMods() = %v (err %v), want shift", got, err)
	}
	if got, err := ev.Action(); err != nil || got != KeyRepeat {
		t.Errorf("Action() = %v (err %v), want KeyRepeat", got, err)
	}
	if got, err := ev.Composing(); err != nil || !got {
		t.Errorf("Composing() = %v (err %v), want true", got, err)
	}
}

// TestKeyEncoderReusesOneEvent feeds many keystrokes through one encoder and
// one event, which is how a hot path should use this.
func TestKeyEncoderReusesOneEvent(t *testing.T) {
	enc, err := NewKeyEncoder()
	if err != nil {
		t.Fatalf("NewKeyEncoder: %v", err)
	}
	defer enc.Close()

	ev, err := NewKeyEvent()
	if err != nil {
		t.Fatalf("NewKeyEvent: %v", err)
	}
	defer ev.Close()

	if err := ev.SetAction(KeyPress); err != nil {
		t.Fatal(err)
	}

	var got string
	for _, r := range "hi" {
		if err := ev.SetKey(KeyA); err != nil { // physical key is irrelevant here
			t.Fatal(err)
		}
		if err := ev.SetUTF8(string(r)); err != nil {
			t.Fatal(err)
		}
		out, err := enc.Encode(ev)
		if err != nil {
			t.Fatalf("Encode: %v", err)
		}
		got += string(out)
	}

	if got != "hi" {
		t.Errorf("reused-event encoding = %q, want %q", got, "hi")
	}
}
