# Mapshot config variables
MAPSHOT_PREFIX="${MAPSHOT_PREFIX:-"mapshot"}"
MAPSHOT_ROOT_DIRECTORY="${MAPSHOT_ROOT_DIRECTORY:-"/opt/mapshot"}"
MAPSHOT_FACTORIO_DATA_DIRECTORY="${MAPSHOT_FACTORIO_DATA_DIRECTORY:-"${MAPSHOT_ROOT_DIRECTORY}/factorio"}"
MAPSHOT_FACTORIO_BINARY_PATH="${MAPSHOT_FACTORIO_BINARY_PATH:-"${MAPSHOT_ROOT_DIRECTORY}/factorio/bin/x64/factorio"}"
MAPSHOT_WORKING_DIRECTORY="${MAPSHOT_WORKING_DIRECTORY:-"${MAPSHOT_ROOT_DIRECTORY}"}"
MAPSHOT_KEEP_ONLY_LATEST="${MAPSHOT_KEEP_ONLY_LATEST:-"false"}"
MAPSHOT_INTERVAL="${MAPSHOT_INTERVAL:-"600"}"
MAPSHOT_SAVE_MODE="${MAPSHOT_SAVE_MODE:-}"
MAPSHOT_SAVE_NAME="${MAPSHOT_SAVE_NAME:-}"

# Factorio config variables
FACTORIO_RELEASE="${FACTORIO_RELEASE:-"stable"}"
FACTORIO_AUTO_UPDATE="${FACTORIO_AUTO_UPDATE:-"true"}"
FACTORIO_SAVE="${FACTORIO_SAVE:-"/opt/factorio/saves/dummy.zip"}"
FACTORIO_SAVE_PATH="${FACTORIO_SAVE_PATH:-$(dirname "${FACTORIO_SAVE}")}"

# runtime variables
MAPSHOT_FACTORIO_SCRIPT_OUTPUT_DIRECTORY="${MAPSHOT_FACTORIO_DATA_DIRECTORY}/script-output"
MAPSHOT_OUTPUT_DIRECTORY="${MAPSHOT_FACTORIO_SCRIPT_OUTPUT_DIRECTORY}/${MAPSHOT_PREFIX}"
FACTORIO_MODS_DIR="${MAPSHOT_FACTORIO_DATA_DIRECTORY}/mods"

trap 'echo "Terminating script..."; exit 0' SIGTERM SIGINT

get_available_factorio_versions() {
	local updater_url="https://updater.factorio.com/get-available-versions?username=${FACTORIO_USERNAME}&token=${FACTORIO_TOKEN}"
	local response http_status response_body

	response=$(curl --location --silent --write-out "%{http_code}" "${updater_url}")
	http_status="${response: -3}"
	response_body="${response%???}"

	if [[ "${http_status}" -ne 200 ]]; then
		printf "Error: Received HTTP status '%s' from Factorio updater.\n" "${http_status}"
		exit 1
	fi

	if ! { echo "${response_body}" | jq . >/dev/null 2>&1; }; then
		printf "Error: Invalid JSON received from Factorio updater. Exiting...\n"
		exit 1
	fi

	printf "%s" "${response_body}"
}

uninstall_factorio() {
	printf "Cleaning up Factorio directory...\n"

	if [[ -d "${MAPSHOT_FACTORIO_DATA_DIRECTORY}" ]]; then
		find "${MAPSHOT_FACTORIO_DATA_DIRECTORY}" -mindepth 1 -type d -not -path "${MAPSHOT_OUTPUT_DIRECTORY}*" -exec rm --recursive --force {} +
		find "${MAPSHOT_FACTORIO_DATA_DIRECTORY}" -mindepth 1 -type f -not -path "${MAPSHOT_OUTPUT_DIRECTORY}/*" -exec rm --force {} +

		printf "Removed old Factorio installation\n"
	else
		printf "Factorio directory does not exist. Skipping cleanup.\n"
	fi
}

download_factorio() {
	local version="${1}"
	local download_file="${MAPSHOT_ROOT_DIRECTORY}/factorio-linux64.tar.xz"
	local download_url="https://www.factorio.com/get-download/${version}/expansion/linux64?username=${FACTORIO_USERNAME}&token=${FACTORIO_TOKEN}"

	printf "Downloading Factorio version: %s...\n" "${version}"
	http_status=$(curl --location --progress-bar --write-out "%{http_code}" --output "${download_file}" "${download_url}")

	if [[ "${http_status}" -ne 200 ]]; then
		printf "Error: Received HTTP status '%s' while attempting to download Factorio version: %s\n" "${http_status}" "${version}"
		exit 1
	fi

	uninstall_factorio

	printf "Extract Factorio version: %s..\n" "${version}"
	tar --extract --xz --verbose --file "${download_file}" --directory "${MAPSHOT_ROOT_DIRECTORY}" || {
		printf "Failed to extract Factorio archive.\n"
		exit 1
	}

	rm --force "${download_file}"
}

validate_credentials() {
	if [[ -z "${FACTORIO_USERNAME:-}" || -z "${FACTORIO_TOKEN:-}" ]]; then
		printf "Authentication not possible. Please set FACTORIO_USERNAME and FACTORIO_TOKEN.\n"
		exit 1
	fi
}

calculate_md5() {
	md5sum "${1}" | awk '{ print $1 }'
}

check_factorio_installation() {
	local installed_factorio_version available_factorio_versions requested_factorio_version

	printf "Checking if Factorio exists...\n"
	if [[ ! -f "${MAPSHOT_FACTORIO_BINARY_PATH}" ]]; then
		printf "Factorio does not exist, downloading...\n"

		validate_credentials
		download_factorio "${FACTORIO_RELEASE}"

		mkdir --parents "${MAPSHOT_FACTORIO_SCRIPT_OUTPUT_DIRECTORY}"
		mkdir --parents "${FACTORIO_MODS_DIR}"
		echo '{}' >"${FACTORIO_MODS_DIR}/mod-list.json"
	else
		printf "Factorio exists, checking version...\n"

		validate_credentials
		installed_factorio_version="$(
			"${MAPSHOT_FACTORIO_BINARY_PATH}" --version |
				grep --only-matching --perl-regexp 'Version: \K\d+\.\d+\.\d+' ||
				printf "Unable to determine the installed version.\n"
			exit 1
		)"

		printf "Installed version: %s\n" "${installed_factorio_version}"

		case "${FACTORIO_RELEASE}" in
		"stable")
			available_factorio_versions="$(get_available_factorio_versions | tail --lines 1)"
			requested_factorio_version="$(
				printf "%s" "${available_factorio_versions}" |
					jq --raw-output '.["core-linux64"][] | select(.stable != null) | .stable'
			)"
			printf "Latest available stable Factorio version: %s\n" "${requested_factorio_version}"
			;;
		"latest")
			available_factorio_versions="$(get_available_factorio_versions | tail --lines 1)"
			requested_factorio_version="$(
				printf "%s" "${available_factorio_versions}" |
					jq --raw-output '.["core-linux64"][] | .to // empty' |
					sort --version-sort |
					tail --lines 1
			)"
			printf "Latest available Factorio version: %s\n" "${requested_factorio_version}"
			;;
		*)
			requested_factorio_version="${FACTORIO_RELEASE}"
			printf "Pinned Factorio version: %s\n" "${requested_factorio_version}"
			;;
		esac

		if [[ "${requested_factorio_version}" == "${installed_factorio_version}" ]]; then
			printf "Factorio is up to date (version: %s).\n" "${installed_factorio_version}"
		else
			printf "Update available: %s -> %s\n" "${installed_factorio_version}" "${requested_factorio_version}"

			if [[ "${FACTORIO_AUTO_UPDATE,,}" =~ ^(true|1|yes)$ ]]; then
				printf "Auto-update is enabled. Proceeding with update...\n"
				download_factorio "${requested_factorio_version}"
				printf "Update completed successfully.\n"
			else
				printf "Auto-update is disabled. Please enable it by setting 'FACTORIO_AUTO_UPDATE=true' if desired.\n"
			fi
		fi
	fi
}

get_factorio_save() {
	local downloaded_file_path="${MAPSHOT_WORKING_DIRECTORY}/$(basename "${FACTORIO_SAVE}")"
	local save_file response http_status

	if [[ "${MAPSHOT_SAVE_MODE}" == "latest" ]]; then
		printf 'MAPSHOT_SAVE_MODE set to "latest". Discovering saves...\n'

		if [[ ! -d "${FACTORIO_SAVE_PATH}" ]]; then
			printf "Error: FACTORIO_SAVE_PATH '%s' does not exist or is not a directory.\n" "${FACTORIO_SAVE_PATH}"
			exit 1
		fi

		save_file=$(find "${FACTORIO_SAVE_PATH}" -type f -exec ls --sort=time {} + 2>/dev/null | head -n 1) || {
			printf "No save files found.\n"
			sleep 30
			continue
		}
		printf "Using latest save: '%s'\n" "${save_file}"
	else
		if [[ -z "${FACTORIO_SAVE:-}" ]]; then
			printf "No save file specified and MAPSHOT_SAVE_MODE is not 'latest'.\n"
			exit 1
		fi

		if [[ "${FACTORIO_SAVE}" =~ ^https?:// ]]; then
			printf "Downloading save file from URL: %s\n" "${FACTORIO_SAVE}"

			response=$(curl --location --silent --write-out "%{http_code}" --output "${downloaded_file_path}" "${FACTORIO_SAVE}")
			http_status="${response: -3}"

			if [[ "${http_status}" -ne 200 ]]; then
				printf "Error: Received HTTP status '%s' while downloading save file.\n" "${http_status}"
				exit 1
			fi

			if [[ ! "${downloaded_file_path}" =~ \.zip$ ]]; then
				printf "Error: Downloaded file '%s' is not a .zip file. Exiting...\n" "${downloaded_file_path}"
				rm --force "${downloaded_file_path}"
				exit 1
			fi

			printf "Save file downloaded to: %s\n" "${downloaded_file_path}"
			save_file="${downloaded_file_path}"
		else
			if [[ ! -f "${FACTORIO_SAVE}" ]]; then
				printf "Error: Specified save file '%s' does not exist.\n" "${FACTORIO_SAVE}"
				exit 1
			fi

			save_file="${FACTORIO_SAVE}"
		fi
	fi

	printf "%s\n" "${save_file}"
}

render_mapshot() {
	local save_file="${1}"

	FACTORIO_VERBOSE_ARG=""
	if [[ "${MAPSHOT_VERBOSE_FACTORIO_LOGGING,,}" =~ ^(true|1|yes)$ ]]; then
		FACTORIO_VERBOSE_ARG="--factorio_verbose"
	fi

	timeout --preserve-status --kill-after 10 --verbose "${MAPSHOT_INTERVAL}" \
		xvfb-run --server-args '-terminate' mapshot render \
		--logtostderr \
		--factorio_binary "${MAPSHOT_FACTORIO_BINARY_PATH}" \
		--factorio_datadir "${MAPSHOT_FACTORIO_DATA_DIRECTORY}" \
		--factorio_scriptoutput "${MAPSHOT_FACTORIO_SCRIPT_OUTPUT_DIRECTORY}" \
		--work_dir "${MAPSHOT_WORKING_DIRECTORY}" \
		--prefix "${MAPSHOT_PREFIX}" \
		--area "${MAPSHOT_AREA:-all}" \
		--tilemin "${MAPSHOT_MINIMUM_TILES:-64}" \
		--tilemax "${MAPSHOT_MAXIMUM_TILES:-0}" \
		--jpgquality "${MAPSHOT_JPEG_QUALITY:-90}" \
		--minjpgquality "${MAPSHOT_MINIMUM_JPEG_QUALITY:-90}" \
		--surface "${MAPSHOT_SURFACES_TO_RENDER:-_all_}" \
		${FACTORIO_VERBOSE_ARG} \
		-v "${MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT:-9}" \
		"${save_file}"
}

move_generated_mapshot() {
	local mapshot_save_path="${1}"
	local mapshot_directory_name="${2}"
	local factorio_save_file_name="${3}"
	local mapshot_json

	printf "Moving generated mapshot to '%s'...\n" "${mapshot_save_path}"

	mkdir --parents "${mapshot_save_path}"
	mv "${MAPSHOT_OUTPUT_DIRECTORY}/${factorio_save_file_name}"/* "${mapshot_save_path}"

	find "${mapshot_save_path}" -mindepth 2 -maxdepth 2 -type f -name "mapshot.json" |
		while read -r mapshot_json; do
			jq --arg savename "${MAPSHOT_SAVE_NAME}" '.savename = $savename' "${mapshot_json}" >"${mapshot_json}.tmp" &&
				mv "${mapshot_json}.tmp" "${mapshot_json}"
		done
}

cleanup_old_mapshots() {
	local mapshot_save_path="${1}"

	if [[ -d "${mapshot_save_path}" ]]; then
		printf "Cleaning up old d-* directories...\n"

		find "${mapshot_save_path}" -maxdepth 1 -type d -name "d-*" |
			sort --reverse | tail --lines +2 |
			while read -r dir; do
				printf "Removing directory: '%s'\n" "${dir}"
				rm --recursive --force "${dir}"
			done

		printf "Cleanup complete.\n"
	else
		printf "No previous mapshot directories to clean in '%s'.\n" "${mapshot_save_path}"
	fi
}

case "${MAPSHOT_MODE}" in
"render")
	printf 'Mapshot mode set to "render".\n'
	check_factorio_installation

	printf "Starting Mapshot loop with timeout of %s seconds...\n" "${MAPSHOT_INTERVAL}"
	while true; do
		factorio_save_file_path="$(get_factorio_save | tail --lines 1)"
		factorio_save_file_name=$(basename "${factorio_save_file_path}" .zip)
		factorio_md5_file="${MAPSHOT_ROOT_DIRECTORY}/${factorio_save_file_name}.md5"
		current_md5=$(calculate_md5 "${factorio_save_file_path}")
		previous_md5=$(cat "${factorio_md5_file}" 2>/dev/null || printf "\n")

		if [[ "${current_md5}" != "${previous_md5}" ]]; then
			mapshot_directory_name="${MAPSHOT_SAVE_NAME:-"${factorio_save_file_name}"}"
			mapshot_save_path="${MAPSHOT_OUTPUT_DIRECTORY}/${mapshot_directory_name}"

			printf "Rendering mapshot...\n"
			render_mapshot "${factorio_save_file_path}"
			printf "%s" "${current_md5}" >"${factorio_md5_file}"

			if [[ -n "${MAPSHOT_SAVE_NAME}" && "${mapshot_directory_name}" != "${factorio_save_file_name}" ]]; then
				move_generated_mapshot "${mapshot_save_path}" "${mapshot_directory_name}" "${factorio_save_file_name}"
			fi

			if [[ "${MAPSHOT_KEEP_ONLY_LATEST,,}" =~ ^(true|1|yes)$ ]]; then
				cleanup_old_mapshots "${mapshot_save_path}"
			fi
		else
			printf "No changes in the save file. Skipping render.\n"
			sleep 30
		fi
	done
	;;
"serve")
	printf 'Mapshot mode set to "serve".\n'

	while true; do
		if [[ -d "${MAPSHOT_OUTPUT_DIRECTORY}" ]]; then
			printf 'Serving mapshot...\n'

			mapshot serve \
				--factorio_scriptoutput "${MAPSHOT_FACTORIO_SCRIPT_OUTPUT_DIRECTORY}" \
				--work_dir "${MAPSHOT_WORKING_DIRECTORY}" \
				-v "${MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT:-9}" || {
				printf "Mapshot serve operation failed.\n"
				exit 1
			}

			break
		else
			printf "Script output directory '%s' does not exist.\n" "${MAPSHOT_OUTPUT_DIRECTORY}"
			sleep 30
		fi
	done
	;;
*)
	printf 'Invalid MAPSHOT_MODE. Please set it to "render" or "serve". Exiting...\n'
	exit 1
	;;
esac

printf "Mapshot successfully completed.\n"
exit 0
