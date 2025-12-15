#!/bin/sh

## Run
rofi -modi emoji \
	 -emoji-format '{emoji}' \
	 -show emoji --emoji-mode copy \
     -theme ~/.config/rofi/styles/emoji.rasi

## Paste The Emoji
PREV_WIN=$(xdotool getwindowfocus)
sleep 0.95
xdotool windowfocus $PREV_WIN
xsel --clipboard --output | xdotool type --delay 0 --file -
