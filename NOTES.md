# My Xkb understanding
My goal is to use `alt_l` as sway modifier, and have `ctrl+alt_l+F1` switch to tty1, and have any other key that can act as `alt` for application shortcuts.

According to my previous understanding `ctrl+alt_l+f1` is a hardcoded thing in kernel and `xkb` has no effect on it. But now I know `xkb` does have a affect but not sure how. ref: https://unix.stackexchange.com/a/63700

Use `xkbcomp $DISPLAY /tmp/keyboard.xkb` to export current xkb config.

I am very vague on this.
Xkb seems to have
- keysym - physical keys
- keycode - physical keys translated to ascii keys, multiple keysym can all represent single keycode
- virtual modifier (Alt, Meta, NumLock, ScrollLock etc.) (search `virtualModifier`)
  - I don't know if applications can access these virtual modifiers but I think they can.
- physical modifier (mod1, mod2, mod3, mod4, Control, Shift, Lock etc.) (search `modifier_map`)


Alt and Meta seem to be same keys?

Now by default:

physical modifier 
  mod1 => alt_l, alt_r, meta_l (all these activate mod1)
virtual modifier 
  alt => alt_l, alt_r (all these activate mod1)
sway
  modifier=mod1 (not actually default but I started as this)


## How do these behave?
If the key represents a virtual modifier, pressing it alone will send `alt_l` to the application, but pressing it in combination will send `alt+l`, I don't think applications can differentiate if `alt_l+l` was pressed or `alt_r+l`, they just know `alt_l` was pressed.

## Attempt 1:
remove `alt_r` from `mod1`, so that it is still part of virtual modifier `alt` but not of `mod1`. Everything works great except that `ctrl+alt_l+F1` no longer switches to tty1 instead `ctrl+alt_r+F1` does that.

The issue is once I have switched to a tty, I have to use `alt_l`, so I have to remeber where I am etc.
Also I don't know what rule getty is using to create this mapping.



NOTE: not too sure about the result of following two attempts, but I surely remember they didn't work.
## Attempt 2:
move `alt_l,meta_l` to `mod3`, use `mod3` in sway. Here for some reason `alt_r` still works in sway.

## Attempt 3:
Remove `alt_l` from `alt` and `mod1` modifier, use the key (not modifier) `alt_l` to bind sway. getty can't switch virtual consoles at all.

