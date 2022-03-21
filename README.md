# Efficient Subtitles

Methods to predict the timing offsets for and apply subtitles to video files when the offset timings are not known.

## Usage

Source `efficient_subtitles.sh` to your bash or zsh shell and use `sub_infer_and_create` to infer a subtitle offset and create a video with subtitles at the appropriate offset.

Provide the following positional parameters:

```bash
> subs_analyze "video.mp4" "subtitles.ass" [overwrite_audio_samples=t] \
  [start_minutes=6] [n_samples_per_sec=10] [intro_skip_seconds=0]
```

If an offset video file or subtitle file needs to be generated, the method will handle this. If none are needed, the method will simply call ffmpeg to combine the original video and audio files.

## Limitations

Only supports ass-type subtitle files at this time.

## Dependencies

- [ffmpeg](https://github.com/FFmpeg/FFmpeg)
- [dev_scripts](https://github.com/tomhallmain/dev_scripts)
