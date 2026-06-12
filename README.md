# USRP-WiFi-Decoder
A USRP-based WiFi signal acquisition and parsing framework that replaces conventional wireless network interface cards with software-defined radio. It supports raw signal capture, baseband processing, frame detection, demodulation, decoding, and IEEE 802.11 packet parsing.

# USRP WiFi SSID Decoder with MATLAB WLAN Toolbox

This repository contains a MATLAB-based offline decoder for WiFi management
frames captured by a USRP B210. It reads interleaved `sc16` IQ samples, detects
802.11 non-HT OFDM packets, performs carrier frequency offset correction and
L-LTF channel estimation, parses L-SIG, demodulates the non-HT data field, and
extracts SSID/BSSID information from Beacon or Probe Response frames.

## Features

- Read USRP B210 `sc16` interleaved I/Q binary captures.
- Normalize and convert raw I/Q samples to complex baseband.
- Detect 802.11 packet preambles with MATLAB WLAN Toolbox.
- Estimate and correct coarse/fine carrier frequency offset.
- Estimate the channel response from L-LTF.
- Parse L-SIG rate and PSDU length fields.
- Recover non-HT data and parse WiFi management frames.
- Export decoded AP information to `output.xlsx`.
- Provide key-step figures for packet detection, channel estimation, L-SIG parsing, and CFO correction.

## Repository Contents

```text
.
|-- decode_usrp_wifi_auto_english.m
|-- decode_usrp_wifi_auto_chinese.m
|-- output.xlsx
|-- usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.bin
|-- usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.zip
|-- usrp_wifi_20260611_085346_ch36_rx2_20Msps_sc16_signal.png
`-- 关键步骤截图/
    |-- key steps (english)/
    `-- key steps (chinese)/
```

The main script for GitHub users is:

```text
decode_usrp_wifi_auto_english.m
```

The Chinese version is kept as a reference:

```text
decode_usrp_wifi_auto_chinese.m
```

## Requirements

- MATLAB
- WLAN Toolbox
- A WiFi IQ capture in one of the supported raw formats:
  - `sc16`: interleaved `int16` I/Q samples
  - `fc32`: interleaved single-precision I/Q samples

The provided capture is configured as:

```text
Sample rate: 20 MS/s
Format: sc16
Channel: WiFi channel 36
Duration: about 0.4314195 s after trimming
```

## Quick Start

1. Clone or download this repository.
2. Open MATLAB.
3. Change MATLAB's current folder to the repository folder.
4. Run:

```matlab
results = decode_usrp_wifi_auto_english;
```

The script automatically searches for the preferred capture file:

```text
usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.bin
```

If that file is not found, it uses the first `.bin` file in the same folder.

## Output

The script prints decoding progress in the MATLAB command window, for example:

```text
USRP B210 WiFi SSID decode
capture: usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.bin
format: sc16
sample_rate: 20000000 Hz
Decode progress: current_index=...
SUMMARY unique_ssids=...
```

It also writes:

```text
output.xlsx
```

The Excel file contains:

- Index
- SSID
- BSSID
- Frame Type
- Start Sample
- MCS
- PSDU Length
- Bit Order
- Frequency Offset Hz
- Capture File

The decoded result structure is also assigned to the MATLAB base workspace:

```matlab
wifi_ssid_results
```

## Key Processing Steps

The folder `关键步骤截图/key steps (english)` contains English-labeled
figures showing the main decoding stages:

```text
01_packet_detection.png
03_lltf_channel_estimation.png
04_lsig_parse.png
05_cfo_three_frequency_lines.png
```

These figures illustrate:

- packet detection and 802.11 preamble field positions
- L-LTF channel magnitude/phase response
- L-SIG bit recovery and field interpretation
- coarse and fine carrier frequency offset estimates

## Capture Format

For `sc16`, the raw binary file stores samples as:

```text
I0, Q0, I1, Q1, I2, Q2, ...
```

where each I and Q value is a signed 16-bit integer. One complex sample uses
4 bytes.

For a 20 MS/s `sc16` capture, the signal duration is:

```text
duration_seconds = file_size_bytes / (20e6 * 4)
```

For example, a file with `34,513,560` bytes contains:

```text
34,513,560 / 4 = 8,628,390 complex samples
8,628,390 / 20,000,000 = 0.4314195 seconds
```

## Notes on GitHub File Size

GitHub's web upload interface has a 25 MiB per-file limit. The trimmed `.zip`
capture in this project is below that limit, but raw IQ captures can easily
exceed normal repository limits.

For larger captures, use one of the following:

- Git command line for files below 100 MiB
- Git LFS for raw signal datasets
- GitHub Releases for downloadable binary assets

Recommended `.gitattributes` entry for Git LFS:

```gitattributes
*.bin filter=lfs diff=lfs merge=lfs -text
*.zip filter=lfs diff=lfs merge=lfs -text
```

## Citation

If this code or capture workflow is useful in your work, please cite the
corresponding project, paper, or dataset release when available.

## License

No license has been specified yet. Add a license file before public reuse or
redistribution.
