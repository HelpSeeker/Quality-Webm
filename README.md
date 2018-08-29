# Quality-Webm
A bash script to simplify the process of making high quality webms.

The goal is to reduce the user input to a single quality parameter.

***

```
Usage: quality.sh [-h] [-p] [-n] [-x threads] [-b custom_bpp] [-f filters]
	
	-h: Show Help.
	-p: Preview theoretical file size.
	-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis.
	-x threads: Specify how many threads to use for encoding. Default value: 1.
	-b custom_bpp: Set a custom bpp value. Default value: 0.1.
	-f filters: Add custom ffmpeg filters.
```

Option | What it does
---------- | ------------
-p | Prints a (very) rough estimate of the resulting file size in MiB. Also shows the used video and audio bitrate.
-n | Switches to the newer codecs VP9/Opus instead of VP8/Vorbis.
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
- [x] Copy input video stream if codec is compatible
- [x] Copy input audio streams if ALL streams have a compatible codec
- [x] Multi-threading by encoding the footage simultaneously in separate parts
- [x] Option to print a rough estimate of the resulting file size
- [x] Allow to switch between VP9/Opus and VP8/Vorbis
- [x] Choose audio bitrate based on channel count when using Vorbis
- [ ] Choose audio bitrate based on channel count when using Opus
- [ ] Differentiate between audio streams with different codecs
- [ ] Let the user choose between VP8/VP9 and Vorbis/Opus separately
- [ ] Option to choose the input video/audio bitrate
- [ ] Free mkv mode. Switches from webm to mkv and allows all free codecs.
