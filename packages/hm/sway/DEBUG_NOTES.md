So, I can't use alt for application shortcuts because sway hijacks them. 

I still want to keep alt_L as alt itself, otherwise ctrl+alt+f1 won't work.
I decided to remove alt_R from mod1 and  tried moving it to mod3 but than only ctrl+alt_R+F1 open the virtual tty and ctrl+alt_L+F1 just results in alt_L+F1 for application. Also tried completely removing alt_R from mod keys.


In virtual consoles only ctrl+alt_l+F1 work. 

`xev` reports the ctrl+alt_R+F1 to be mapping to virtual console, but not sure why getty or whoever handles this is not happy. Well for now, no Alt shortcuts for applications


Resorting to using Super instead of Alt as sway modifier, but it hurts ... literally.
