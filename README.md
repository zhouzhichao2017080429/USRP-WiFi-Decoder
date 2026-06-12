# USRP-WiFi-Decoder
A USRP-based WiFi signal acquisition and parsing framework that replaces conventional wireless network interface cards with software-defined radio. It supports raw signal capture, baseband processing, frame detection, demodulation, decoding, and IEEE 802.11 packet parsing.

这是一个基于 USRP 的 WiFi 信号采集与解析框架，使用软件定义无线电替代传统无线网卡。该框架支持原始信号采集、基带处理、帧检测、解调、译码以及 IEEE 802.11 数据包解析。
（不能代替无线网卡，只能用于WiFi信号分析）

# USRP WiFi SSID Decoder with MATLAB WLAN Toolbox
# 基于 MATLAB WLAN Toolbox 的 USRP WiFi SSID 解码器

This repository contains a MATLAB-based offline decoder for WiFi management frames captured by a USRP B210.

本仓库包含一个基于 MATLAB 的离线解码程序，用于解析 USRP B210 采集到的 WiFi 管理帧。

It reads interleaved `sc16` IQ samples, detects 802.11 non-HT OFDM packets, corrects carrier frequency offset, estimates the L-LTF channel, parses L-SIG, demodulates non-HT data, and extracts SSID/BSSID information.

程序读取交织存储的 `sc16` IQ 采样，检测 802.11 non-HT OFDM 包，完成载波频偏校正、L-LTF 信道估计、L-SIG 解析、non-HT 数据解调，并提取 SSID/BSSID 信息。

## Features
## 功能特点

- Read USRP B210 `sc16` interleaved I/Q binary captures.
- 读取 USRP B210 的 `sc16` 交织 I/Q 二进制采集文件。
- Convert raw I/Q samples to normalized complex baseband samples.
- 将原始 I/Q 采样转换为归一化的复数基带信号。
- Detect 802.11 packet preambles with MATLAB WLAN Toolbox.
- 使用 MATLAB WLAN Toolbox 检测 802.11 包前导码。
- Estimate and correct coarse/fine carrier frequency offset.
- 估计并校正粗频偏和细频偏。
- Estimate the channel response from L-LTF.
- 基于 L-LTF 估计信道响应。
- Parse L-SIG rate and PSDU length fields.
- 解析 L-SIG 中的速率字段和 PSDU 长度字段。
- Recover non-HT data and parse WiFi management frames.
- 恢复 non-HT 数据字段并解析 WiFi 管理帧。
- Export decoded AP information to `output.xlsx`.
- 将解析出的 AP 信息导出到 `output.xlsx`。
- Provide key-step figures for packet detection, channel estimation, L-SIG parsing, and CFO correction.
- 提供包检测、信道估计、L-SIG 解析和频偏校正等关键步骤截图。

## Repository Contents
## 仓库内容

The main files and folders are organized as follows.
主要文件和文件夹组织如下。

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

The main script for English output is `decode_usrp_wifi_auto_english.m`.
英文输出版本的主脚本是 `decode_usrp_wifi_auto_english.m`。

The Chinese version is kept as a reference in `decode_usrp_wifi_auto_chinese.m`.
中文版本保留在 `decode_usrp_wifi_auto_chinese.m` 中，作为参考。

## Requirements
## 环境依赖

- MATLAB.
- MATLAB。
- WLAN Toolbox.
- WLAN Toolbox。
- A WiFi IQ capture in a supported raw format.
- 一份支持格式的 WiFi IQ 原始采集数据。
- Supported formats include `sc16` and `fc32`.
- 支持的格式包括 `sc16` 和 `fc32`。

For `sc16`, samples are stored as interleaved signed 16-bit I/Q values.
对于 `sc16`，采样以有符号 16 位 I/Q 交织形式存储。

For `fc32`, samples are stored as interleaved single-precision I/Q values.
对于 `fc32`，采样以单精度 I/Q 交织形式存储。

## Provided Capture
## 提供的采集数据

The provided trimmed capture is configured as follows.
当前提供的截取后采集数据配置如下。

```text
Sample rate: 20 MS/s
Format: sc16
Channel: WiFi channel 36
Duration: about 0.4314195 s after trimming
```

The preferred input file used by the script is listed below.
脚本优先读取的输入文件如下。

```text
usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.bin
```

## Quick Start
## 快速开始

Clone or download this repository.
克隆或下载本仓库。

Open MATLAB.
打开 MATLAB。

Change MATLAB's current folder to the repository folder.
将 MATLAB 当前工作目录切换到本仓库文件夹。

Run the following command.
运行以下命令。

```matlab
results = decode_usrp_wifi_auto_english;
```

The script automatically searches for the preferred `.bin` capture file in the same folder.
脚本会自动在同一文件夹中查找优先使用的 `.bin` 采集文件。

If the preferred file is not found, the script uses the first `.bin` file in the same folder.
如果找不到优先文件，脚本会读取同一文件夹中的第一个 `.bin` 文件。

## Output
## 输出结果

The script prints decoding progress in the MATLAB command window.
脚本会在 MATLAB 命令行窗口中打印解析进度。

Example command-line output is shown below.
命令行输出示例如下。

```text
USRP B210 WiFi SSID decode
capture: usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.bin
format: sc16
sample_rate: 20000000 Hz
Decode progress: current_index=...
SUMMARY unique_ssids=...
```

The script writes the decoded table to `output.xlsx`.
脚本会将解码表格写入 `output.xlsx`。

The Excel file contains the following columns.
Excel 文件包含以下列。

- Index.
- 序号。
- SSID.
- WiFi 名称 SSID。
- BSSID.
- 接入点 BSSID。
- Frame Type.
- 帧类型。
- Start Sample.
- 起始采样点。
- MCS.
- MCS。
- PSDU Length.
- PSDU 长度。
- Bit Order.
- 比特顺序。
- Frequency Offset Hz.
- 频偏，单位 Hz。
- Capture File.
- 采集数据文件。

The decoded result structure is also assigned to the MATLAB base workspace.
解析结果结构体也会写入 MATLAB base workspace。

```matlab
wifi_ssid_results
```

## Key Processing Steps
## 关键处理步骤

The folder `关键步骤截图/key steps (english)` contains English-labeled figures for the main decoding stages.
文件夹 `关键步骤截图/key steps (english)` 中保存了主要解码步骤的英文标注图片。

The folder `关键步骤截图/key steps (chinese)` contains the corresponding Chinese-labeled figures.
文件夹 `关键步骤截图/key steps (chinese)` 中保存了对应的中文标注图片。

The English key-step figures include the following files.
英文关键步骤图片包括以下文件。

```text
01_packet_detection.png
03_lltf_channel_estimation.png
04_lsig_parse.png
05_cfo_three_frequency_lines.png
```

These figures show packet detection and 802.11 preamble field positions.
这些图片展示了包检测和 802.11 前导字段位置。

They also show L-LTF channel magnitude/phase response, L-SIG bit recovery, and carrier frequency offset correction.
它们还展示了 L-LTF 信道幅度/相位响应、L-SIG 比特恢复和载波频偏校正。

## Capture Format
## 采集数据格式

For `sc16`, the raw binary file stores samples in the following order.
对于 `sc16`，原始二进制文件按如下顺序存储采样。

```text
I0, Q0, I1, Q1, I2, Q2, ...
```

Each I and Q value is a signed 16-bit integer.
每个 I 和 Q 值都是一个有符号 16 位整数。

One complex sample uses 4 bytes.
一个复数采样点占用 4 字节。

For a 20 MS/s `sc16` capture, the signal duration is calculated as follows.
对于 20 MS/s 的 `sc16` 采集，信号时长计算如下。

```text
duration_seconds = file_size_bytes / (20e6 * 4)
```

For example, a file with `34,513,560` bytes contains `8,628,390` complex samples.
例如，大小为 `34,513,560` 字节的文件包含 `8,628,390` 个复数采样点。

At 20 MS/s, this corresponds to `0.4314195` seconds.
在 20 MS/s 采样率下，对应时长为 `0.4314195` 秒。

```text
34,513,560 / 4 = 8,628,390 complex samples
8,628,390 / 20,000,000 = 0.4314195 seconds
```

## Notes on GitHub File Size
## GitHub 文件大小说明

GitHub's web upload interface has a 25 MiB per-file limit.
GitHub 网页上传接口对单个文件有 25 MiB 的限制。

Raw IQ captures can easily exceed normal repository limits.
原始 IQ 采集文件很容易超过普通 Git 仓库的文件大小限制。

For larger captures, use Git command line, Git LFS, or GitHub Releases.
对于更大的采集文件，可以使用 Git 命令行、Git LFS 或 GitHub Releases。

Git LFS is recommended for raw `.bin` signal datasets.
对于原始 `.bin` 信号数据集，推荐使用 Git LFS。

GitHub Releases are useful for downloadable binary assets that should not be stored directly in Git history.
GitHub Releases 适合存放不希望直接进入 Git 历史的大型二进制下载文件。

Recommended `.gitattributes` entries for Git LFS are shown below.
推荐的 Git LFS `.gitattributes` 配置如下。

```gitattributes
*.bin filter=lfs diff=lfs merge=lfs -text
*.zip filter=lfs diff=lfs merge=lfs -text
```

## Citation
## 引用

If this code or capture workflow is useful in your work, please cite the corresponding project, paper, or dataset release when available.
如果本代码或采集流程对你的工作有帮助，请在可用时引用对应的项目、论文或数据集发布版本。

## License
## 许可证

No license has been specified yet.
目前尚未指定许可证。

Please add a license file before public reuse or redistribution.
在公开复用或再分发之前，请添加许可证文件。


Please add a license file before public reuse or redistribution.
在公开复用或再分发之前，请添加许可证文件。

No license has been specified yet. Add a license file before public reuse or
redistribution.
