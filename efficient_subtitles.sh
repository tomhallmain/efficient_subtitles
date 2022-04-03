

# NOTE these functions require installation of https://github.com/tomhallmain/dev_scripts


sub_infer_and_create() { # Run sub analysis and create combined sub file with result: sub_infer_and_create video_file sub_file [overwrite_audio_samples=t] [start_minutes=6] [intro_skip_seconds=0] [n_samples_per_sec=10]
    echo -e "Executing command: subs_analyze $@ | read -r optimal_samplevar_seconds_offset"
    local video_file="$1"
    local sub_file="$2"
    local intro_skip_seconds="$5"
    local n_samples_per_sec="$6"
    subs_analyze $@ | read -r optimal_samplevar_seconds_offset
    let local optimal_samplevar="$(echo "$optimal_samplevar_seconds_offset" | awk '{print $1}')"
    let local retry_count=0
    if [[ "$3" && "$3" -eq 1 ]]; then
        let local retry_at_minute=2
    else
        let local retry_at_minute=1
    fi
    while [[ "$optimal_samplevar" -gt 1500 && "$retry_count" -lt 9 ]]; do
        echo -e "Found sample variance was too high. Retrying with new offset minutes: $retry_at_minute"
        echo -e "Executing command: subs_analyze \"$video_file\" \"$sub_file\" f $retry_at_minute \"$intro_skip_seconds\" \"$n_samples_per_sec\" | read -r optimal_samplevar_seconds_offset"
        subs_analyze "$video_file" "$sub_file" f "$retry_at_minute" "$intro_skip_seconds" "$n_samples_per_sec" | read -r optimal_samplevar_seconds_offset
        let local optimal_samplevar="$(echo "$optimal_samplevar_seconds_offset" | awk '{print $1}')"
        let local retry_count+=1
        let local retry_at_minute+=1
        if [[ ! "$3" && $retry_at_minute -eq 6 ]]; then # skip default value of 6
            let local retry_at_minute+=1
        fi
    done
    local optimal_seconds_offset="$(echo "$optimal_samplevar_seconds_offset" | awk '{print $2}')"
    if [ "$optimal_seconds_offset" ]; then
        echo -e "Executing command: get_subs_force_retimed \"$video_file\" \"$sub_file\" -\"$optimal_seconds_offset\" \"$intro_skip_seconds\""
        get_subs_force_retimed "$video_file" "$sub_file" -"$optimal_seconds_offset" "$intro_skip_seconds"
    else
        echo -e "Executing command: get_sub_with_adjustment \"$video_file\" \"$sub_file\" \"$intro_skip_seconds\""
        get_sub_with_adjustment "$video_file" "$sub_file" "$intro_skip_seconds"
    fi
}

get_sub_with_adjustment() { # Get video file with subs timing adjustment: get_sub_with_offset video_file subs_file [offset_secs_from_base=0] [test_duration]
    ds:is_int "$1" ds:fail 'Integer arg required for arg 1'
    local OLD_PWD="$(pwd)"
    IFS=$'\t' read -r _dirpath _filename _extension <<<"$(ds:path_elements "$1")"
    local video_file_dir="$_dirpath"
    local output_file="${_dirpath}${_filename}-subs.mp4"
    cd "$video_file_dir"
    echo 'Executing command'
    if ds:test '[0-9]{1,2}:[0-9]{1,2}' "$3"; then
        local duration="$3"
        echo "Creating video with test duration: $duration"
        local _test_duration=(-t "$duration")
    else
        unset _test_duration
    fi
    if [ -f "$1" ]
    then
        local video_input="$1"
        shift
    else
        ds:fail "Video file not provided or invalid: \"$1\""
    fi
    if [ -f "$1" ]
    then
        local sub_file="$1"
        shift
    else
        ds:fail "Subtitle file not provided or invalid: \"$1\""
    fi
    if [ ! "$1" ]
    then
        echo -e "ffmpeg -i \"${video_input}\" -vf \"ass=${sub_file}\" -b:v 20M -c:a copy ${output_file}"
        ffmpeg -i "${video_input}" -vf "ass=${sub_file}" ${_test_duration[@]} -b:v 20M -c:a copy "$output_file"
        local stts=$?
    elif $(echo "$1" | awk '{if($0 > 0) exit; else exit 1}')
    then
        local positive_offset="$(echo "$1" | get_time_string 1 t)"
        echo -e "ffmpeg -ss ${positive_offset} -i \"${video_input}\" -vf \"ass=${sub_file}\" -b:v 20M -c:a copy ${output_file}"
        ffmpeg -ss "${positive_offset}" -i "${video_input}" -vf "ass=${sub_file}" ${_test_duration[@]} -b:v 20M -c:a copy "$output_file"
        local stts=$?

        #local tmp_video_file=".subs_with_adjustment_temp.mp4"
        #echo -e "\n\nCreating new temporary video file at ${tmp_video_file}\n\n"
        #echo -e "ffmpeg -ss 00:00:${positive_offset} -i \"${video_input}\" \"${tmp_video_file}\""
        #ffmpeg -ss 00:00:${positive_offset} -i "${video_input}" ${_test_duration[@]} -y "${tmp_video_file}"
        #echo -e "\n\n Adding subs to new video...\n\n"
        #echo -e "ffmpeg -i \"${tmp_video_file}\" -i \"${sub_file}\" ${output_file}"
        #ffmpeg -i "${tmp_video_file}" -i "${sub_file}" ${output_file}
        #rm "$tmp_video_file"
    else
        local seconds_back="$(echo "$1" | sed 's#-##g' | get_time_string 1 t)"
        echo -e "Creating new sub file at .subs_file_with_adjustment_1.ass"
        echo -e "ffmpeg -ss \"${seconds_back}\" -i \"${sub_file}\" -y .subs_file_with_adjustment.ass"
        ffmpeg -ss "${seconds_back}" -i "${sub_file}" ${_test_duration[@]} -y .subs_file_with_adjustment.ass
        echo -e "Applying new subs file to original video"
        echo -e "ffmpeg -i \"${video_input}\" -i .subs_file_with_adjustment.ass $output_file"
        ffmpeg -i "${video_input}" -i .subs_file_with_adjustment.ass "$output_file"
        local stts=$?
        rm .subs_file_with_adjustment.ass
    fi
    if [[ $stts -eq 0 && -f "$output_file" ]]
    then
        echo -e "Saved combined video and audio file at $output_file"
    else
        echo -e "There was a problem creating combined video and audio file at $output_file"
    fi
    cd "$OLD_PWD"
}

get_subs_force_retimed() { # Create new subtitle file with timing adjustment: get_subs_force_retimed video_file sub_file [secs_back=0] [intro_skip_seconds=0] [test_duration]
    [[ -f "$1" && -f "$2" ]] || ds:fail 'Video / subtitle files not provided or invalid'
    local OLD_PWD="$(pwd)"
    local video_file="$1"
    local video_file_dir="$(dirname "$video_file")"
    cd "$video_file_dir"
    local sub_file="${2}"
    local secs_back="${3:-0}"
    local intro_skip_seconds="$4"
    local test_duration="$5"
    local events_sec_at="$(grep -hIno '^\[Events\]' "$sub_file" | sed -E 's#:.*##g')"
    let local subs_start_at=$events_sec_at+2
    IFS=$'\t' read -r __dirpath __filename __extension <<<"$(ds:path_elements "$sub_file")"
    local new_sub_file="${__dirpath}${__filename}-retimed.ass"
    ds:reo "$sub_file" "NR<${subs_start_at}" off > "${new_sub_file}"
    echo >> "${new_sub_file}"
    ds:reo "$sub_file" "NR>${subs_start_at}" off | ds:reo a 1 f -v FS=, > /tmp/_subs_left_data
    ds:reo "$sub_file" "NR>${subs_start_at}" off | ds:reo a 2 f -v FS=, > /tmp/_subs_start
    ds:reo "$sub_file" "NR>${subs_start_at}" off | ds:reo a 3 f -v FS=, > /tmp/_subs_end
    ds:reo "$sub_file" "NR>${subs_start_at}" off | ds:reo a 'NF>3' f -v FS=, > /tmp/_subs_right_data
    # NOTE this only works if difference < 60 seconds positive or negative
    local SUBS_TIMING_ADJUSTMENT_PROGRAM='
    {
        if ($3 > 59.99) {
            if ($3 > 999) {
                next
            }

            seconds = $3 - 60
            seconds_string = seconds > 9.99 ? seconds : "0" seconds

            if (!(seconds_string ~ "\\.") && length(seconds_string) < 4) {
                seconds_string = seconds_string ".00"
            }
            else if (length(seconds_string) < 5) {
                seconds_string = seconds_string "0"
            }

            minutes = $2 + 1
            minutes_string = minutes > 9 ? minutes : "0" minutes
            print $1 FS minutes_string FS seconds_string
        }
        else if ($3 >= 0) {
            seconds = $3 + 0
            seconds_string = seconds > 9.99 ? seconds : "0" seconds

            if (!(seconds_string ~ "\\.") && length(seconds_string) < 4) {
                seconds_string = seconds_string ".00"
            }
            else if (length(seconds_string) < 5) {
                seconds_string = seconds_string "0"
            }

            print $1 FS $2 FS seconds_string
        }
        else {
            if ($3 < -999) {
                next
            }

            seconds = 60 + $3
            seconds_string = seconds > 9.99 ? seconds : "0" seconds

            if (!(seconds_string ~ "\\.") && length(seconds_string) < 4) {
                seconds_string = seconds_string ".00"
            }
            else if (length(seconds_string) < 5) {
                seconds_string = seconds_string "0"
            }

            minutes = $2 - 1
            minutes_string = minutes > 9 ? minutes : "0" minutes
            print $1 FS minutes_string FS seconds_string
        }
    }'
    ds:agg /tmp/_subs_start "0+\$3${secs_back}" '+' -v FS=':' | ds:reo a 1,2,4 \
            | awk -F: "$SUBS_TIMING_ADJUSTMENT_PROGRAM" > /tmp/_subs_start_retimed
    ds:agg /tmp/_subs_end "0+\$3${secs_back}" '+' -v FS=':' | ds:reo a 1,2,4 \
            | awk -F: "$SUBS_TIMING_ADJUSTMENT_PROGRAM" > /tmp/_subs_end_retimed
    paste /tmp/_subs_left_data /tmp/_subs_start_retimed /tmp/_subs_end_retimed \
            /tmp/_subs_right_data  > /tmp/_subs_recombined
    cat /tmp/_subs_recombined \
            | ds:reo '2~^[0-9:\.]+$ && 3~^[0-9:\.]+$' a -v FS=$'\t' \
            | sed -E 's#\t#,#g' \
            | awk '{gsub(/\015.*$/, "\015");print}' \
            >> "${new_sub_file}"
    rm /tmp/_subs_left_data /tmp/_subs_start /tmp/_subs_end /tmp/_subs_right_data \
            /tmp/_subs_start_retimed /tmp/_subs_end_retimed /tmp/_subs_recombined

    echo "\n\nSaved new sub file at: ${new_sub_file}\n\n"
    get_sub_with_adjustment "$video_file" "${new_sub_file}" "$intro_skip_seconds" "$test_duration"
    cd "$OLD_PWD"
}

subs_analyze() { # Calculate most likely offset for subs compared to video: subs_analyze video_file sub_file [overwrite_audio_samples=t] [start_minutes=6] [intro_skip_seconds=0] [n_samples_per_sec=10]
    [[ -f "$1" && -f "$2" ]] || ds:fail 'Video / subtitle files not provided or invalid'
    local video_file="${1}"; shift
    local sub_file="${1}"; shift
    local overwrite_audio_samples="${1:-t}"
    local start_minutes="${2:-6}"
    local intro_skip_seconds="${3:-0}"
    local n_samples_per_sec="${4:-10}"
    ds:is_int "$start_minutes" || ds:fail "Invalid start_minutes arg: ${start_minutes}"
    ds:is_int "$n_samples_per_sec" || ds:fail "Invalid n_samples_per_sec arg: ${n_samples_per_sec}"
    ds:is_int "$intro_skip_seconds" || ds:fail "Invalid intro_skip_seconds arg: ${intro_skip_seconds}"
    let local asetnsamples=44100/$n_samples_per_sec
    let local extra_intro_skip_samples="${intro_skip_seconds}*${n_samples_per_sec}"
    let local actual_intro_skip_samples="${start_minutes}*60*${n_samples_per_sec}"
    local actual_intro_skip_samples="${actual_intro_skip_samples%.*}"
    let local sample_minutes=6
    let local sample_samples="${sample_minutes}*60*${n_samples_per_sec}"
    let local head_samples="${actual_intro_skip_samples}+${sample_samples}"
    let local offset_samples="45*$n_samples_per_sec"
    let local offset_sample_samples=$sample_samples+$offset_samples
    let local offset_head_samples=$head_samples+$offset_samples
    local events_sec_at="$(grep -hIno '^\[Events\]' "$sub_file" | sed -E 's#:.*##g')"
    let local subs_start_at=$events_sec_at+2
    [ -d /tmp/subs_analyze ] || mkdir /tmp/subs_analyze
    ds:reo "$sub_file" "NR>${subs_start_at}" off | ds:reo a 2,3 f -v FS=, -v OFS=":" > /tmp/subs_analyze/sub_timing_data
    echo "Samples per second: $n_samples_per_sec" >&2
    echo "Offset samples: $offset_samples" >&2
    echo "" >&2
    awk -F: -v n_samples_per_sec="$n_samples_per_sec" '{
            for (i = 1; i < 7; i++) {
                if (!($i >= 0 && $i ~ /^[0-9]+(\.[0-9]+)?$/)) {
                    next
                }
            }
            on_switch_time_val_secs = GetTimeSeconds($1, $2, $3)
            on_switch_sample_index = int(on_switch_time_val_secs * n_samples_per_sec)
            on_switch_samples[on_switch_sample_index] = 1
            off_switch_time_val_secs = GetTimeSeconds($4, $5, $6)
            off_switch_sample_index = int(off_switch_time_val_secs * n_samples_per_sec)
            off_switch_samples[off_switch_sample_index] = 1
            max_sample_index = off_switch_sample_index
        }

        END {
            on = 0
            for (sample_i = 1; sample_i <= max_sample_index; sample_i++) {
                if (sample_i in on_switch_samples) {
                    on = 1
                }
                else if (sample_i in off_switch_samples) {
                    on = 0
                }
                print on
            }
        }

        function GetTimeSeconds(hours, mins, secs) {
            hours = hours * 60 * 60
            mins = mins * 60
            return hours + mins + secs
        }' /tmp/subs_analyze/sub_timing_data \
            | head -n $offset_head_samples \
            | tail -n $offset_sample_samples > /tmp/subs_analyze/sub_switching_with_offsets
    if ds:test '(t|true)' "$overwrite_audio_samples"; then
        echo "Gathering audio samples..." >&2
        ffmpeg -i "$video_file" -af "asetnsamples=${asetnsamples},astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=log.txt" -f null - >&2
        echo "Saved audio samples file: log.txt" >&2
    else
        echo "Using preconstructed audio samples: log.txt" >&2
    fi
    echo "First ${intro_skip_seconds} seconds audio skipped" >&2
    echo "First ${start_minutes} minutes skipped" >&2
    echo "Getting ${sample_minutes} minutes of samples for comparison" >&2
    rg 'lavfi.astats.Overall.RMS_level=' log.txt \
            | sed 's#lavfi.astats.Overall.RMS_level=##g' \
            | ds:decap $extra_intro_skip_samples \
            | head -n $head_samples \
            | tail -n $sample_samples \
            | awk '{gsub("-inf", -150, $0); print (150 + $0)}' > /tmp/subs_analyze/base_samples
    awk 'BEGIN{counts=0}
        $0 && ($0 + 0) == $0 {
            counts++
            sum += $0
            stream[NR] = $0 + 0
        }
        END {
            mean = sum / counts
            for (i = 1; i <= counts; i++) {
                if (stream[i] > mean) {
                    print 1
                }
                else {
                    print 0
                }
            }
        }
        ' /tmp/subs_analyze/base_samples > /tmp/subs_analyze/audio_switching
    echo "Switching samples obtained, calculating optimal sample offset" >&2
    let local last_sample_index=$offset_samples-1
    for ((i=0; i<$offset_samples; i++)); do
        awk -v offset=$i -v offset_end_base=$sample_samples 'NR >= offset && NR <= offset_end_base + offset {
            print $0
        }' /tmp/subs_analyze/sub_switching_with_offsets > "/tmp/subs_analyze/sub_switching_splits${i}"
        let local to_paste_files_tally="$i%100"
        if [[ $to_paste_files_tally -eq 99 || $i -eq $last_sample_index ]]; then
            echo /tmp/subs_analyze/sub_switching_splits* | ds:transpose | sort -V | xargs paste > "/tmp/subs_analyze/sub_switching_base_splits${i}"
            rm /tmp/subs_analyze/sub_switching_splits*
        fi
    done
    echo /tmp/subs_analyze/sub_switching_base_splits* | ds:transpose | sort -V | xargs paste | sed -E 's#\t#,#g' > /tmp/subs_analyze/possible_switching.csv
    rm /tmp/subs_analyze/sub_switching_base_splits*
    awk '{for (i = 0; i < '$offset_samples'; i++) printf "%s,", $0; print $0}' /tmp/subs_analyze/audio_switching > /tmp/subs_analyze/audio_base.csv
    ds:diff_fields /tmp/subs_analyze/possible_switching.csv /tmp/subs_analyze/audio_base.csv 'b' > /tmp/subs_analyze/diffs
    awk -F, '{for(f=1;f<=NF;f++)sums[f]+=$f}END{for(f=1;f<=NF;f++)print sums[f] " " f}' /tmp/subs_analyze/diffs \
            | sort -V > /tmp/subs_analyze/diff_totals
    echo "Saved files: " /tmp/subs_analyze/* >&2
    head -n 30 /tmp/subs_analyze/diff_totals | get_time_string "$n_samples_per_sec" >&2
    local optimal_offset_data="$(head -n1 /tmp/subs_analyze/diff_totals | get_time_string "$n_samples_per_sec")"
    echo "$optimal_offset_data" | awk '{if ($2 > 0.4) print $0; else print $1}'
}


get_time_string() {
  awk -v full_string="${2:-0}" '{
          if (only_time && $2) {
              print GetTimeString($2)
          }
          else if ( !$2 ) {
              print GetTimeString($1)
          }
          else {
              print $1 " " GetTimeString($2)
          }
      }
      function GetTimeString(sample_index) {
          time_string = ""
          hours = 0
          minutes = 0
          seconds = sample_index / '${1:-1}'
          if (seconds > 3600) {
              hours = int(seconds / 3600)
              seconds = seconds % 3600
          }
          if (seconds > 60) {
              minutes = int(seconds / 60)
              seconds = seconds % 60
          }
          if (hours > 0) {
              if (minutes < 10) {
                  if (seconds < 10) {
                      time_string = hours ":0" minutes ":0" seconds
                  }
                  else {
                      time_string = hours ":0" minutes ":" seconds
                  }
              }
              else if (seconds < 10) {
                  time_string = hours ":" minutes ":0" seconds
              }
              else {
                  time_string hours ":" minutes ":" seconds
              }

              if (full_string && length(hours) < 2) {
                  return "0" time_string
              }
              else {
                  return time_string
              }
          }
          else if (minutes > 0) {
              if (seconds < 10) {
                  time_string = minutes ":0" seconds
              }
              else {
                  time_string = minutes ":" seconds
              }

              if (full_string) {
                  if (length(minutes) < 2) {
                      return "00:0" time_string
                  }
                  else {
                      return "00:" time_string
                  }
              }
              else {
                  return time_string
              }
          }
          else if (full_string) {
              if (length(seconds) < 2) {
                  return "00:00:0" seconds
              }
              else {
                  return "00:00:" seconds
              }
          }
          else {
              return seconds
          }
      }'
}
