use log *
# https://www.reddit.com/r/AV1/comments/n4si96/encoder_tuning_part_3_av1_grain_synthesis_how_it/
# https://www.reddit.com/r/AV1/comments/18l0k07/svt_vs_nvenc_comparisons_for_av1/
# https://trac.ffmpeg.org/wiki/Encode/AV1
# https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Ffmpeg.md

# preset: 3, 4
# film-grain: 6 8 10 15 # check links
# quality: check links? 24 - 30 I guess
# With the best options from the above:
# check tune on
# enable-tf
# enable-qm + film-grain-denoise just to get a better understanding of what the effects are and if they are useable at all

export def "main encode av1 custom-preset" [
	input_path: path,
	--preset: int = 4, # Recommended values for overall preset is either 3, 4, or 5. Where 3 takes considerably longer than 4.
	--film-grain: int = 8, # Recommended to start with 8 for live action and 15 for noisy movies like 'Indiana Jones'
	--crf: int = 26, # Vastly different recommendations and depends on the preset. Recommendations going from 24 to 30
	--film-grain-denoise: bool = false, # Usually recommendation to disable denoising because the simple denoising takes too long with little benefit.
	--tune: bool = false, # Should always be false, as this optimizes for visual appeal and not PSNR.
	--enable-tf: bool = false, # Currently, more people recommend to disable temporal filtering as it produces 'blurry' videos even if individual frames look better.
	--enable-qm: bool = true, # No really clear how this affects the output. But some recommend to enable it to reduce the file size without many people being able to tell the difference.
	--duration-sec: int = -1, # By default everything is encoded but with this option the encoding will stop after the given amount of seconds.
	--start-sec: int = -1, # start offset
	--num-samples: int = 0, # If provided, the input file length is split into `num-samples` chunks and encoded until `stop-sec` have passed. Requires `stop-sec` to be set and ignores `start-sec` 
] {
	let encopts = $"preset=($preset):crf=($crf):film-grain-denoise=($film_grain_denoise | into int):film-grain=($film_grain):enable-tf=($enable_tf | into int):enable-qm=($enable_qm | into int):qm-min=0:tune=($tune | into int)"
	let duration_opt = match $duration_sec {
		-1 => [],
		$val => ["-t" $val]
	}
	# should the num_samples be processed in parallel? yeah, but make the number of parallel workers configurable in doubt
	let start_opts = match $num_samples {
		0 => (
			match $start_sec {
				-1 => [[]],
				$val => [["-ss" $val]]
			}
		),
		$num => {
			# maybe requires some magic to get to the correct stream: BDMV/STREAM/00000.m2ts 
			let movie_length_sec = ffprobe -v error -show_entries format=duration -print_format default=noprint_wrappers=1:nokey=1 $input_path | into float | into int
			info $"Movie duration in seconds is: ($movie_length_sec)"
			1..$num | each {
				|f|
				($f + ($f - 1)) / (2 * $num_samples) * $movie_length_sec} # split into num_samples chunks and start from the middle of those chunks to not get 'boring' start/end frames
				| each { |startsec| ["-ss" $startsec] }
		}
	}

	# hash encode options for output directory and write a metadata file with the encoding options in a sorted, nice manner
	let opts = [
	 	# Ordering is important! Input should usually come first!
		-i $"($input_path)"
		-stats
		-c:a copy
		-c:v libsvtav1
		-pix_fmt yuv420p10le
		-g 240
		-svtav1-params $"($encopts)"
		-map_chapters 0 # TODO: Understand if this works!
		-c:s mov_text # TODO: Understand if this copies the subtitles!
		-y # overwrite 
	] ++ $duration_opt 
	# ++ [
	# 	$"sample_output.mkv"
	# ]
	let opt_hash = ( $opts | sort | str join " " | hash sha256 )
	mkdir $opt_hash
	$opts | save -f $"($opt_hash)/config.txt"
	$start_opts | par-each {
		|start_opt| 
		let t = $start_opt.1
		# seek offset should come first because we want to skip over the INPUT not the
		# output!
		^ffmpeg ($start_opt ++ $opts ++ [$"($opt_hash)/sample_($t).mkv"])
	}

	# ^$cmd <- is broken and should be removed from https://www.nushell.sh/book/working_with_strings.html#bare-strings
	# Also use for describe in match documentation should be dropped
}

export def main [] {}

