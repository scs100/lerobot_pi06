#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  monitor_system_resources.sh [-i interval_seconds] [-c sample_count] [-o log_file]

Options:
  -i    Sampling interval in seconds (default: 2)
  -c    Number of samples (default: 0, means infinite)
  -o    Log file path (optional)
  -h    Show this help

Examples:
  ./scripts/monitor_system_resources.sh
  ./scripts/monitor_system_resources.sh -i 1 -c 30
  ./scripts/monitor_system_resources.sh -i 2 -o /tmp/resource_monitor.log
EOF
}

INTERVAL="2"
COUNT="0"
LOG_FILE=""

while getopts ":i:c:o:h" opt; do
  case "$opt" in
    i) INTERVAL="$OPTARG" ;;
    c) COUNT="$OPTARG" ;;
    o) LOG_FILE="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "ERROR: Option -$OPTARG requires an argument." >&2
      usage
      exit 2
      ;;
    \?)
      echo "ERROR: Invalid option -$OPTARG" >&2
      usage
      exit 2
      ;;
  esac
done

if ! [[ "$INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "ERROR: interval must be a positive number." >&2
  exit 2
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: sample_count must be a non-negative integer." >&2
  exit 2
fi

emit_line() {
  local line="$1"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$line" | tee -a "$LOG_FILE"
  else
    printf '%s\n' "$line"
  fi
}

format_bytes() {
  local bytes="$1"
  awk -v b="$bytes" '
    BEGIN {
      split("B KiB MiB GiB TiB PiB", u, " ");
      i=1;
      while (b >= 1024 && i < 6) { b /= 1024; i++; }
      if (i == 1) printf "%.0f%s", b, u[i];
      else printf "%.2f%s", b, u[i];
    }
  '
}

read_cpu_stat() {
  local line
  read -r line < /proc/stat
  # shellcheck disable=SC2086
  set -- $line
  # cpu user nice system idle iowait irq softirq steal guest guest_nice
  local user="$2" nice="$3" system="$4" idle="$5" iowait="$6" irq="$7" softirq="$8" steal="$9"
  local busy=$((user + nice + system + irq + softirq + steal))
  local total=$((busy + idle + iowait))
  printf '%s %s %s\n' "$busy" "$total" "$iowait"
}

read_disk_stat() {
  local read_sectors=0
  local write_sectors=0
  local io_ms=0
  local major minor dev reads_completed reads_merged sectors_read ms_reading
  local writes_completed writes_merged sectors_written ms_writing ios_in_progress ms_doing_io weighted_ms_doing_io

  while read -r major minor dev reads_completed reads_merged sectors_read ms_reading \
    writes_completed writes_merged sectors_written ms_writing ios_in_progress ms_doing_io weighted_ms_doing_io; do
    [[ "$dev" =~ ^(loop|ram|sr|fd|zram) ]] && continue
    [[ "$dev" =~ ^sd[a-z][0-9]+$ ]] && continue
    [[ "$dev" =~ ^vd[a-z][0-9]+$ ]] && continue
    [[ "$dev" =~ ^xvd[a-z][0-9]+$ ]] && continue
    [[ "$dev" =~ ^nvme[0-9]+n[0-9]+p[0-9]+$ ]] && continue
    [[ "$dev" =~ ^mmcblk[0-9]+p[0-9]+$ ]] && continue

    read_sectors=$((read_sectors + sectors_read))
    write_sectors=$((write_sectors + sectors_written))
    io_ms=$((io_ms + ms_doing_io))
  done < /proc/diskstats

  printf '%s %s %s\n' "$read_sectors" "$write_sectors" "$io_ms"
}

read_mem_stat() {
  awk '
    /^MemTotal:/ {mt=$2}
    /^MemAvailable:/ {ma=$2}
    /^SwapTotal:/ {st=$2}
    /^SwapFree:/ {sf=$2}
    END {
      mem_used=mt-ma;
      swap_used=st-sf;
      printf "%d %d %d %d\n", mt, mem_used, st, swap_used;
    }
  ' /proc/meminfo
}

gpu_snapshot() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf 'N/A'
    return
  fi
  nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
    --format=csv,noheader,nounits 2>/dev/null | awk -F',' '
      {
        gsub(/^ +| +$/, "", $1);
        gsub(/^ +| +$/, "", $2);
        gsub(/^ +| +$/, "", $3);
        gsub(/^ +| +$/, "", $4);
        gsub(/^ +| +$/, "", $5);
        gsub(/^ +| +$/, "", $6);
        gsub(/^ +| +$/, "", $7);
        printf "GPU%s:%s util=%s%% mem=%s/%sMiB temp=%sC pwr=%sW; ", $1, $2, $3, $4, $5, $6, $7;
      }
    ' | sed 's/[;[:space:]]*$//'
}

disk_usage_snapshot() {
  df -hP / | awk 'NR==2 {printf "%s used=%s avail=%s use=%s", $1, $3, $4, $5}'
}

read -r prev_busy prev_total prev_iowait < <(read_cpu_stat)
read -r prev_read_sectors prev_write_sectors prev_io_ms < <(read_disk_stat)

header="time | cpu% | iowait% | loadavg(1/5/15) | mem_used/total | swap_used/total | disk_r/s | disk_w/s | disk_busy% | rootfs | gpu"
emit_line "$header"

sample_idx=0
while :; do
  sleep "$INTERVAL"

  read -r cur_busy cur_total cur_iowait < <(read_cpu_stat)
  read -r cur_read_sectors cur_write_sectors cur_io_ms < <(read_disk_stat)
  read -r mem_total_kb mem_used_kb swap_total_kb swap_used_kb < <(read_mem_stat)
  read -r load1 load5 load15 _ < /proc/loadavg

  busy_delta=$((cur_busy - prev_busy))
  total_delta=$((cur_total - prev_total))
  iowait_delta=$((cur_iowait - prev_iowait))

  cpu_pct="$(awk -v b="$busy_delta" -v t="$total_delta" 'BEGIN { if (t<=0) printf "0.0"; else printf "%.1f", (b*100.0)/t }')"
  iowait_pct="$(awk -v iw="$iowait_delta" -v t="$total_delta" 'BEGIN { if (t<=0) printf "0.0"; else printf "%.1f", (iw*100.0)/t }')"

  read_sector_delta=$((cur_read_sectors - prev_read_sectors))
  write_sector_delta=$((cur_write_sectors - prev_write_sectors))
  io_ms_delta=$((cur_io_ms - prev_io_ms))

  # Linux sectors are typically 512 bytes.
  read_bps="$(awk -v s="$read_sector_delta" -v i="$INTERVAL" 'BEGIN { if (i<=0) print 0; else printf "%.0f", (s*512.0)/i }')"
  write_bps="$(awk -v s="$write_sector_delta" -v i="$INTERVAL" 'BEGIN { if (i<=0) print 0; else printf "%.0f", (s*512.0)/i }')"
  disk_busy_pct="$(awk -v ms="$io_ms_delta" -v i="$INTERVAL" 'BEGIN { if (i<=0) print "0.0"; else printf "%.1f", (ms/(i*10.0)); }')"

  mem_total_b=$((mem_total_kb * 1024))
  mem_used_b=$((mem_used_kb * 1024))
  swap_total_b=$((swap_total_kb * 1024))
  swap_used_b=$((swap_used_kb * 1024))

  mem_str="$(format_bytes "$mem_used_b")/$(format_bytes "$mem_total_b")"
  swap_str="$(format_bytes "$swap_used_b")/$(format_bytes "$swap_total_b")"
  disk_r_str="$(format_bytes "$read_bps")/s"
  disk_w_str="$(format_bytes "$write_bps")/s"
  rootfs_str="$(disk_usage_snapshot)"
  gpu_str="$(gpu_snapshot)"
  ts="$(date '+%F %T')"

  emit_line "$ts | $cpu_pct | $iowait_pct | $load1/$load5/$load15 | $mem_str | $swap_str | $disk_r_str | $disk_w_str | $disk_busy_pct | $rootfs_str | $gpu_str"

  prev_busy="$cur_busy"
  prev_total="$cur_total"
  prev_iowait="$cur_iowait"
  prev_read_sectors="$cur_read_sectors"
  prev_write_sectors="$cur_write_sectors"
  prev_io_ms="$cur_io_ms"

  sample_idx=$((sample_idx + 1))
  if [[ "$COUNT" -gt 0 && "$sample_idx" -ge "$COUNT" ]]; then
    break
  fi
done
