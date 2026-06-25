#!/bin/bash

# ---------------------------------------------------------------
# ab_video_avi2mp4.sh
#
# Converts a set of AVI files to MP4 using ffmpeg.
# Output files are saved in the ./media directory.
#
# Encoding settings:
#   -c:v libx264   H.264 video codec
#   -crf 23        Quality level (lower = better; 18-28 is typical)
#   -preset medium Encoding speed/compression trade-off
#   -c:a aac       AAC audio codec
#
# Usage:
#   ./ab_video_avi2mp4.sh
#
# Requirements:
#   ffmpeg must be installed and available in PATH
#   Install via conda: conda install -c conda-forge ffmpeg
#
# Output:
#   ./media/<filename>.mp4
# ---------------------------------------------------------------

# Create media directory if it doesn't exist
mkdir -p media

# Convert each AVI to MP4
ffmpeg -i cardio-lvilla.avi -c:v libx264 -crf 23 -preset medium -c:a aac media/cardio-lvilla.mp4
ffmpeg -i cardio-lvilla_noaudio.avi -c:v libx264 -crf 23 -preset medium -c:a aac media/cardio-lvilla_noaudio.mp4
ffmpeg -i cardio-lvilla_trimmed.avi -c:v libx264 -crf 23 -preset medium -c:a aac media/cardio-lvilla_trimmed.mp4
ffmpeg -i cardio-lvilla_bw.avi -c:v libx264 -crf 23 -preset medium -c:a aac media/cardio-lvilla_bw.mp4
ffmpeg -i cardio-lvilla_bw_inset.avi -c:v libx264 -crf 23 -preset medium -c:a aac media/cardio-lvilla_bw_inset.mp4
ffmpeg -i cardio-lvilla_bw_inset_108sec.avi -c:v libx264 -crf 23 -preset medium -c:a aac media/cardio-lvilla_bw_inset_108sec.mp4
