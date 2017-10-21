#!/bin/bash

# Author: Brain of Terror, Dublin Roller Derby.
# License: Apache 2.0

# This script will allow you to stream a webcam to Youtube, with an overlay
# from the CRG scoreboard. It also saves a copy of the video locally.

# If the connection to Youtube breaks, the local copy will still be made and
# once the connection is working again the livestream will continue on from
# where it was. There may be warnings about "Past duration 0.973076 too large"
# when this happens - these are harmless.

# This was written to work on Linux (Ubuntu in particular, with ffmpeg
# 2.8.11-0ubuntu0.16.04.1). It's currently a bit raw, and presumes you that you
# know what you're doing when it comes to computers.

# To use:
# - Setup CRG as you usually would. 
# - Prepare a separate machine for video encoding.
#   Encoding is CPU intensive, it needs its own machine not doing anything else.
# - Enable your Youtube account for livestreaming (it's under Creator Studio).
# - Put your stream key in $HOME/.youtube_key
# - Ensure you can access CRG from the video machine (network setup left as exercise for the reader).
# - apt-get install ffmpeg alsa-utils
# - Disable screensaver/power saving on video machine.
# - If using a laptop, make sure it's on mains power.
# - Set the various variables below as needed.
# - Make sure the current directory has space for the local copy of the videos.
# - Run this script in a loop in case it crashes: while true; do ./stream.sh; done
# - Load the scoreboard overlay from CRG in your browser, and fullscreen it (F11).
# - Make sure mouse pointer isn't visible.
# - Don't touch anything until the bout is over.

# About 20 seconds later, the livestream should show up on Youtube. It will
# likely take some trial and error to get all the settings right. Make sure
# you've CPU, disk space and internet bandwidth to spare.
# It would be wise to try this out at scrimmage before using it at a full game.


# Camera device. Likely video0 or video1.
CAMERA_DEVICE="/dev/video0"
# Supported resolutions and encodings can be found with "ffmpeg -f v4l2 -list_formats all -i /dev/video0"
# This is also the output resolution. Reduce if you're having problems.
CAMERA_RESOLUTION="1280x720"
CAMERA_ENCODING="mjpeg"
# Framerate. Reduce if you're having problems.
FRAMERATE="25"
# Output video bitrate. Bigger means better picture, but more network bandwidth and disk space.
# See also https://support.google.com/youtube/answer/2853702?hl=en&ref_topic=6136989
# Rule of thumb: 1024kb/s for a 2 hour bout is around 1GB.
BITRATE="1024k"

# Where to take audio from, "arecord -l" lists possible devices 
# Device 0 Card 1 is hw:1,0
ALSA_AUDIO_DEVICE="hw:2,0"

# The resolution of your machine's display.
SCOREBOARD_RESOLUTION="1920x1080"


# Settings below here should not need to be touched.


# The Youtube stream key is taken from a file called .youtube_key in your home directory,
# so that you don't accidentally include it in this script.
YOUTUBE_KEY=$(<$HOME/.youtube_key)

AUDIO_IN="-f alsa -ac 1 -thread_queue_size 10240 -i $ALSA_AUDIO_DEVICE"
CAMERA_IN="-f v4l2 -framerate $FRAMERATE -video_size $CAMERA_RESOLUTION -thread_queue_size 1024 -i $CAMERA_DEVICE"
SCOREBOARD_IN="-f x11grab -framerate $FRAMERATE -video_size ${SCOREBOARD_RESOLUTION/x/,} -thread_queue_size 1024 -i :0.0+0,0"

# Chromakey the scoreboard to make green transparant
# Scale the scoreboard to the same size as camera
# Overlay the scoreboard on the camera
FILTER="
  [2:v]colorkey=0x00ff00:.01:1[ckout];
  [ckout]scale=${CAMERA_RESOLUTION}[scaleout];
  [1:v][scaleout]overlay[out]
"

ENCODE="-vcodec libx264 -pix_fmt yuv420p -preset veryfast -r $FRAMERATE -g $FRAMERATE -b:v $BITRATE -codec:a libmp3lame -ar 44100 -threads 4 -b:a 64k -bufsize $BITRATE"

OUTFILE="out-$(date +%Y-%m-%d-%H%M%S).flv"


# Start the encoder, write to local disk.
ffmpeg $AUDIO_IN $CAMERA_IN $SCOREBOARD_IN \
  -filter_complex "$FILTER" -map '[out]:v' -map 0:a \
  $ENCODE -f flv $OUTFILE &
ENCODE_PID=$!

# Stop the encoder when the script stops.
function cleanup {
  kill $ENCODE_PID
}
trap cleanup EXIT

# Wait a bit for encoder to write the file, then stream that to youtube.
sleep 10
ffmpeg -re -i $OUTFILE -c copy -f flv rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY

