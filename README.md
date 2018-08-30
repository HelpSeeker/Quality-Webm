# Quality-Webm
A bash script to simplify the process of making high quality webms.

The goal is to reduce the user input to a single quality parameter.

***

```
Usage: quality.sh [-h] [-p] [-n] [-x threads] [-b custom_bpp] [-f filters]
	
	-h: Show Help.
	-p: Preview theoretical file size.
	-n: Use the newer video codec VP9 instead of VP8..
	-x threads: Specify how many threads to use for encoding. Default value: 1.
	-b custom_bpp: Set a custom bpp value. Default value: 0.1.
	-f filters: Add custom ffmpeg filters.
```

Option | What it does
---------- | ------------
-p | Prints a rough estimate of the resulting file size in MiB. Also shows the used video and audio bitrate.
-n | Switches to the newer video codec VP9. This will lead to a much better compression, but also reduces the encoding speed immensely. Best used with multi-threading.
-x threads | Enables multi-threading for a faster conversion. **This isn't libvpx's multi-threading and doesn't come with its weird limitations!** See [this related wiki page](https://github.com/HelpSeeker/Restricted-Webm/wiki/Fast-encoding-mode) for more information.
-b custom_bpp | Sets a custom bits per pixel value. Higher values result in a higher quality. Takes resolution and frame rate into account and adjusts the video bitrate accordingly. Default value: 0.1.
-f filters | Adds a custom filter string to the ffmpeg command. The filters entered will get passed down as is. Any mistakes in the filter syntax will throw errors. See [ffmpeg's documentation on filters](https://ffmpeg.org/ffmpeg-filters.html) for more details.

***

**Requirements:**  
ffmpeg (with libvpx, libvpx-vp9, libvorbis and libopus enabled)  
ffprobe  
```
Folder structure:

Quality-Webm/
│
├── quality.sh
│
├── to_convert/
      │ 
      │ file01
      │ file02
      │ file03
      │ ...

```

***

Functionality (both implemented and planned):

- [x] Adjust video bitrate based on bpp value
- [x] Smart stream copying. Webm-compatible streams will be copied, unless user set filters prevent it
- [x] Multi-threading by encoding the footage simultaneously in separate parts
- [x] Option to print an estimate of the resulting file size
- [x] Allow to switch between VP9 and VP8
- [x] Use Opus as standard audio codec
- [x] Use Vorbis as fallback codec, if Opus encoding fails (see [this bug tracker](https://trac.ffmpeg.org/ticket/5718))
- [x] Set audio bitrate for each audio stream based on the channel count
- [x] Switch to mkv container, if image-based subtitles are being used ([as the conversion from image- to text-based subtitles isn't trivial](https://linux.goeszen.com/extract-subtitles-with-ffmpeg-from-a-ts-video-file.html))
- [ ] Option to choose the input video/audio bitrate
- [ ] Free mkv mode. Switches from webm to mkv and allows all free codecs
- [ ] Include bitrate of copied video streams in the file size preview
