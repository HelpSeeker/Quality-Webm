#!/bin/bash

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Default settings
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

new_codecs=false
parallel_convert=false
parallel_afilter=false
ask_parallel_afilter=true

parallel_process=1
bpp=0.1

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Function to define help text for the -h flag
usage() {
	echo -e "Usage: $0 [-h] [-n] [-x threads] [-b custom_bpp] [-f filters]"
	
	echo -e "\\t-h: Show Help."
	echo -e "\\t-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis."
	echo -e "\\t-x threads: Specify how many threads to use for encoding. Default value: 1."
	echo -e "\\t-b custom_bpp: Set a custom bpp value. Default value: 0.2."
	echo -e "\\t-f filters: Add custom ffmpeg filters."
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Look for certain substring $2 within a string $1
# If substring is found (e.i. $1 contains the substring) -> Success
contains() {
	case "$1" in 
		*"$2"*) return 0;;
		*) return 1;;
	esac
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

info() {
	video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
			-of default=noprint_wrappers=1:nokey=1 "$input")
		
	video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
			-of default=noprint_wrappers=1:nokey=1 "$input")

	frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
			-of default=noprint_wrappers=1:nokey=1 "$input")
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Determine height/width of the output, when a user defined scale filter is being used
filterTest() {
	ffmpeg -y -hide_banner -loglevel panic -i "$input" \
		-t 1 -c:v libvpx -deadline good -cpu-used 5 \
		-filter_complex $filter_settings -an "../done/${input%.*}.webm"
	
	# Read user set height/width from the test webm
	video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	
	video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

videoSettings() {
	if [[ "$new_codecs" = true ]]; then 
		video_codec="libvpx-vp9"
	else
		video_codec="libvpx"
	fi
	
	video_bitrate=$(bc <<< "$bpp*$video_height*$video_width*$frame_rate/1000")
	
	video="-c:v $video_codec -slices 8 -threads 1 -deadline good -cpu-used 0 \
		-qmin 1 -qmax 50 -b:v ${video_bitrate}K -tune ssim -auto-alt-ref 1 \
		-lag-in-frames 25 -arnr-maxframes 15 -arnr-strength 3"
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

audioSettings() {
	if [[ "$new_codecs" = true ]]; then 
		audio_codec="libopus"
		audio="-c:a $audio_codec -ar 48000 -b:a 192K"
	else
		audio_codec="libvorbis"
		audio="-c:a $audio_codec -ar 48000 -q:a 10"
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

concatenate() {
	if [[ -z "$filter_settings" ]]; then
		filter=""
	else
		filter="-filter_complex $filter_settings"
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

codecCheck() {
	copy_audio=false
	copy_video=false
	
	acodec_list=("Vorbis" "Opus")
	vcodec_list=("VP8" "VP9")
	input_info=$(ffprobe -v error -show_streams -of default=noprint_wrappers=1:nokey=1 "$input")
					
	for acodec in ${acodec_list[@]}
	do
		contains "$input_info" "$acodec" && copy_audio=true
	done
	
	for vcodec in ${acodec_list[@]}
	do
		contains "$input_info" "$vcodec" && copy_video=true
	done
	
	if [[ "$copy_audio" = true ]]; then
		audio="-c:a copy"
		mkdir test
		ffmpeg -loglevel panic -i "$input" -t 1 -map 0:a? -c:a copy "test/output.webm" || audioSettings
		rm -rf test
	fi
	
	if [[ "$copy_video" = true ]]; then
		video="-c:v copy"
		mkdir test
		ffmpeg -loglevel panic -i "$input" -t 1 -map 0:v -c:v copy "test/output.webm" || videoSettings
		rm -rf test
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

convert() {
	ffmpeg -y -hide_banner -i "$input" \
		-map 0:v -map 0:a? -map 0:s? \
		$video -sn -an $filter -pass 1 -f webm /dev/null
		
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
				
	ffmpeg -y -hide_banner -i "$input" \
		-map 0:v -map 0:a? -map 0:s? -c:s copy -metadata title="${input%.*}" \
		$video $audio $filter -pass 2 "../done/${input%.*}.webm"
		
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
		
	rm ffmpeg2pass-0.log 2> /dev/null
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Read user set flags
while getopts ":hnx:b:f:" ARG; do
	case "$ARG" in
	h) usage && exit;;
	n) new_codecs=true;;
	x) parallel_process="$OPTARG" && parallel_convert=true;;
	g) height="$OPTARG";;
	b) bpp="$OPTARG";;
	f) filter_settings="$OPTARG";;
	*) echo "Unknown flag used. Use $0 -h to show all available options." && exit;;
	esac;
done

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Change into sub-directory to avoid file conflicts when converting webms
cd to_convert 2> /dev/null || { echo "No to_convert folder present" && exit; }

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Make sure there are any files in to_convert/
for file in *
do 
	[[ -e "$file" ]] || { echo "No files present in to_convert" && exit; }
	break
done

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Create sub-directory for the finished webms
mkdir ../done 2> /dev/null

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Main conversion loop
for input in *; do (
	info
	if [[ -n "$filter_settings" ]]; then filterTest; fi
	videoSettings
	audioSettings
	concatenate
	codecCheck
	convert
); done
