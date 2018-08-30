#!/bin/bash

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Default settings
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

new_codecs=false
parallel_convert=false
preview=false

parallel_process=1
bpp=0.1

acodec_list=("Vorbis" "Opus")
vcodec_list=("VP8" "VP9")
extension="webm"

afilters=false
vfilters=false

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Function to define help text for the -h flag
usage() {
	echo -e "Usage: $0 [-h] [-p] [-n] [-x threads] [-b custom_bpp] [-f filters]"
	
	echo -e "\\t-h: Show Help."
	echo -e "\\t-p: Preview theoretical file size."
	echo -e "\\t-n: Use the newer video codec VP9 instead of VP8."
	echo -e "\\t-x threads: Specify how many threads to use for encoding. Default value: 1."
	echo -e "\\t-b custom_bpp: Set a custom bpp value. Default value: 0.1."
	echo -e "\\t-f filters: Add custom ffmpeg filters."
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

showPreview() {
	file_size=$(bc <<< "($video_bitrate+$complete_audio)*$length/8/1024")
	
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo "File: $input"
	echo "Video bitrate: ${video_bitrate}Kbps | Audio bitrate (all streams combined): ${complete_audio}Kbps"
	echo "Theoretical file size: ${file_size}MiB"
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
			
	length=$(ffprobe -v error -show_entries format=duration \
			-of default=noprint_wrappers=1:nokey=1 "$input")
			
	for (( i=0; i<100; i++ ))
	do
		index=$(ffprobe -v error -select_streams a:$i -show_entries stream=index \
			-of default=noprint_wrappers=1:nokey=1 "$input")
		if [[ "$index" = "" ]]; then
			audio_streams=$i
			break;
		fi
	done
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Determine height/width of the output, when a user defined scale filter is being used
filterTest() {
	mkdir test
	
	ffmpeg -y -hide_banner -loglevel panic -i "$input" \
		-t 1 -c:v libvpx -deadline good -cpu-used 5 \
		-filter_complex $filter_settings -an "test/output.$extension"
	
	# Read user set height/width from the test webm
	video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
					-of default=noprint_wrappers=1:nokey=1 "test/output.$extension")
	
	video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
					-of default=noprint_wrappers=1:nokey=1 "test/output.$extension")
					
	ffmpeg -loglevel panic -i "$input" -t 1 -map 0:v -c:v copy \
		-filter_complex "$filter_settings" "test/video.$extension" || vfilters=true
	ffmpeg -loglevel panic -i "$input" -t 1 -map 0:a? -c:a copy \
		-filter_complex "$filter_settings" "test/audio.$extension" || afilters=true
	
	rm -rf test
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
	
	video_first="-c:v $video_codec -slices 8 -threads 1 -deadline good -cpu-used 5 \
		-qmin 1 -qmax 50 -b:v ${video_bitrate}K"

	video_second="-c:v $video_codec -slices 8 -threads 1 -deadline good -cpu-used 0 \
		-qmin 1 -qmax 50 -b:v ${video_bitrate}K -tune ssim -auto-alt-ref 1 \
		-lag-in-frames 25 -arnr-maxframes 15 -arnr-strength 3"
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

audioSettings() {
	audio=""
	complete_audio=0

	for (( j=0; j<audio_streams; j++ ))
	do
		channels=$(ffprobe -v error -select_streams a:$j -show_entries stream=channels \
			-of default=noprint_wrappers=1:nokey=1 "$input")
		input_audio_codec=$(ffprobe -v error -select_streams a:0:$j \
			-show_entries stream=codec_long_name -of default=noprint_wrappers=1:nokey=1 "$input")
		
		copy_audio=false			
		for acodec in ${acodec_list[@]}
		do
			contains "$input_audio_codec" "$acodec" && copy_audio=true
		done
	
		if [[ "$copy_audio" = true && "$afilters" = false ]]; then
			mkdir test
			ffmpeg -loglevel panic -i "$input" -map 0:a:$j -c:a copy "test/output.webm"
			input_audio_bitrate=$(ffprobe -v error -show_entries format=bit_rate \
					-of default=noprint_wrappers=1:nokey=1 "test/output.$extension")
			rm -rf test
			
			audio_bitrate=$(bc <<< "$input_audio_bitrate/1000")
			(( complete_audio += audio_bitrate ))
		
			audio="${audio}-c:a:$j copy "
		else
			audio_codec="libopus"
		
			mkdir test
			ffmpeg -loglevel panic -i "$input" -t 1 -map 0:a:$j \
				-c:a:$j libopus "test/output.$extension" || audio_codec="libvorbis"
			rm -rf test
	
			(( audio_bitrate = channels * 96 ))
			(( complete_audio += audio_bitrate ))

			audio="${audio}-c:a:$j $audio_codec -b:a:$j ${audio_bitrate}K "
		fi
	done
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
	copy_video=false
	image_sub=false
	
	input_info=$(ffprobe -v error -show_streams -of default=noprint_wrappers=1:nokey=1 "$input")
	
	for vcodec in ${vcodec_list[@]}
	do
		contains "$input_info" "$vcodec" && copy_video=true
	done
	
	if [[ "$copy_video" = true && "$vfilters" = false ]]; then
		video_first="-c:v copy"
		video_second="-c:v copy"
	else
		copy_video=false
	fi
	
	ffmpeg -loglevel panic -i "$input" -map 0:s? -c:s webvtt "temp/sub.vtt" || image_sub=true
	
	if [[ "$image_sub" = true ]]; then
		extension="mkv"
		subtitles="-c:s copy"
	else
		extension="webm"
		subtitles="-c:s webvtt"
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

convert() {
	ffmpeg -y -hide_banner -i "$input" -map 0:v \
		$video_first $filter -pass 1 -f webm /dev/null
		
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
				
	ffmpeg -y -hide_banner -sub_charenc UTF-8 -i "$input" \
		-map 0:v -map 0:a? -map 0:s? $subtitles -metadata title="${input%.*}" \
		$video_second $audio $filter -pass 2 "../done/${input%.*}.$extension"
		
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
		
	rm ffmpeg2pass-0.log 2> /dev/null
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

multiConvert() {
	parallel_duration=$(bc <<< "scale=3; $length/$parallel_process")
	
	mkdir temp
	
	for (( j=0; j<parallel_process; j++ ))
	do	
	{
		parallel_start=$(bc <<< "scale=3; $parallel_duration*$j")
	
		mkdir temp/$j
		cd temp/$j || { echo "Error in multiConvert! No dir temp/$j present." && exit; }
		
		ffmpeg -y -hide_banner -ss $parallel_start -i "../../$input" \
			-t $parallel_duration -map 0:v $video_first $filter -pass 1 -f webm /dev/null
		
		echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
				
		ffmpeg -y -hide_banner -ss $parallel_start -i "../../$input" \
			-t $parallel_duration -map 0:v $video_second $filter -pass 2 "${j}.$extension"
		
		echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
		
		cd ../..
	} &
	done
	
	wait
	
	for (( j=0; j<parallel_process; j++ ))
	do
		echo "file 'temp/${j}/${j}.$extension'" >> list.txt
	done
	
	ffmpeg -loglevel panic -f concat -i list.txt -c copy "temp/video.webm"
	if [[ "$afilters" = true ]]; then
		ffmpeg -hide_banner -i "$input" -map 0:a? -r 1 $filter $audio "temp/audio.ogg"
	else
		ffmpeg -hide_banner -i "$input" -map 0:a? $audio "temp/audio.ogg"
	fi
	
	ffmpeg -y -loglevel panic -i temp/video.webm -i temp/audio.ogg -sub_charenc UTF-8 -i "$input" \
		-map 0:v -map 1:a? -map 2:s? -c:v copy -c:a copy $subtitles \
		-metadata title="${input%.*}" "../done/${input%.*}.$extension"
			
	rm -rf list.txt temp/
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Read user set flags
while getopts ":hpnx:b:f:" ARG; do
	case "$ARG" in
	h) usage && exit;;
	p) preview=true;;
	n) new_codecs=true;;
	x) parallel_process="$OPTARG" && parallel_convert=true;;
	b) bpp="$OPTARG";;
	f) filter_settings="$OPTARG";;
	*) echo "Unknown flag used. Use $0 -h to show all available options." && exit;;
	esac;
done

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Revert back to normal convert if <= 1 thread is specified
if (( parallel_process <= 1 )); then parallel_convert=false; fi

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
for input in *
do
	info
	if [[ -n "$filter_settings" ]]; then filterTest; fi
	videoSettings
	audioSettings
	codecCheck
	concatenate
	
	if [[ "$preview" = true ]]; then
		showPreview
	else
		if [[ "$parallel_convert" = true && "$copy_video" = false ]];then 
			multiConvert
		else
			convert
		fi
	fi	
done
