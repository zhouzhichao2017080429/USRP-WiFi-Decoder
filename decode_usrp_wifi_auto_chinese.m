function results = decode_usrp_wifi_auto()
%DECODE_USRP_WIFI_AUTO 使用 USRP B210 采集的 IQ 数据解析 WiFi 的 SSID/BSSID。
%
% 作者：zhouzhichao
% 日期：2026年6月12日
%
% 代码内容：
%   本程序读取同目录下的一份 USRP B210 WiFi 电磁信号采集数据
%   （sc16 交织 IQ 二进制文件），用 MATLAB WLAN Toolbox 完成
%   802.11 非 HT OFDM 信号的包检测、频偏校正、信道估计、LSIG 解析、
%   Non-HT 数据区解调，并从 Beacon / Probe Response 管理帧中提取
%   WiFi 名称 SSID、接入点 BSSID、帧类型、起始采样点等信息。
%
% 操作流程：
%   1. 自动定位本 .m 文件所在文件夹；
%   2. 优先读取同目录中的 ch36 USRP 采集数据；
%   3. 将 sc16 交织 I/Q 数据还原为复数基带信号；
%   4. 进行包检测、粗/细频偏校正、L-LTF 信道估计；
%   5. 解析 LSIG 得到候选长度和速率，再尝试 Non-HT 解调；
%   6. 把解调出的比特转换为 MPDU 字节，解析 SSID/BSSID；
%   7. 按“当前解析位置 / 全信号长度”打印解析进度百分比；
%   8. 打印解析结果，并把结果结构体保存到 MATLAB 工作区变量
%      wifi_ssid_results；
%   9. 将扫描解析结果输出为同目录下的 Excel 文件 output.xlsx。
%
% 运行结束条件：
%   程序扫描到采集文件末尾、后续没有检测到新的 WiFi 包、包长度越界，
%   或达到 maxPackets 设置的最大包数时结束。结束前会打印 SUMMARY，
%   显示成功解析出的唯一 SSID/BSSID 数量，并生成 output.xlsx。
%
% Usage in MATLAB:
%   cd('D:\无线通信网络认知\TPAMI\USRP+MATLAB+Python\auto code')
%   results = decode_usrp_wifi_auto;
%
% 注意：运行前本文件夹只需要包含本代码和一份 sc16 IQ .bin 采集数据；
%       运行结束后会自动生成 output.xlsx。

clc;

% 获取当前脚本所在文件夹，使代码可以直接在 auto code 目录中运行。
scriptDir = fileparts(mfilename('fullpath'));

% 这份 ch36 数据在之前的解析结果中识别到的 AP 数量最多，因此优先使用。
preferredCapture = 'usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.bin';
captureFile = fullfile(scriptDir, preferredCapture);

% 如果优先文件不存在，就自动读取同目录下找到的第一份 .bin 数据。
if exist(captureFile, 'file') ~= 2
    files = dir(fullfile(scriptDir, '*.bin'));
    if isempty(files)
        error('No .bin USRP IQ capture was found in: %s', scriptDir);
    end
    captureFile = fullfile(files(1).folder, files(1).name);
end

% USRP 采集参数：20 MS/s，sc16 表示 int16 I/Q 交织存储。
sampleRate = 20e6;
captureFormat = 'sc16';
maxComplexSamples = inf;
maxPackets = inf;

fprintf('USRP B210 WiFi SSID decode\n');
fprintf('capture: %s\n', captureFile);
fprintf('format: %s\n', captureFormat);
fprintf('sample_rate: %.0f Hz\n\n', sampleRate);

% 主解析函数：读取 IQ，完成 WiFi PHY/MAC 解析，返回唯一 SSID/BSSID 列表。
results = decodeCapture(captureFile, sampleRate, captureFormat, maxComplexSamples, maxPackets);

% 将解析结果保存为 Excel，文件名固定为 output.xlsx，便于后续查看和整理。
outputFile = fullfile(scriptDir, 'output.xlsx');
writeResultsExcel(results, captureFile, outputFile);

% 命令行输出最终汇总，便于直接查看解析到了哪些 WiFi AP。
fprintf('\nSUMMARY unique_ssids=%d\n', numel(results));
if isempty(results)
    fprintf('No SSID/BSSID was decoded. Try another channel capture or a longer capture.\n');
else
    for k = 1:numel(results)
        fprintf('%2d. SSID=%s  BSSID=%s  frame=%s  start=%d  mcs=%d  len=%d  cfo=%.1f Hz\n', ...
            k, results(k).ssid, results(k).bssid, results(k).subtype, ...
            results(k).start_sample, results(k).mcs, results(k).psdu_length, results(k).cfo_hz);
    end
end

% 把结果放入 MATLAB base workspace，方便后续手动查看、保存或继续分析。
assignin('base', 'wifi_ssid_results', results);
fprintf('\nResult struct was also assigned to workspace variable: wifi_ssid_results\n');
fprintf('Excel output was saved to: %s\n', outputFile);
end


function results = decodeCapture(infile, fs, fmt, maxComplex, maxPackets)
% 读取 USRP IQ 文件，并调用 WLAN Toolbox 对 802.11 OFDM 包进行离线解析。

fid = fopen(infile, 'rb');
if fid < 0
    error('Cannot open capture file: %s', infile);
end
fileCleanup = onCleanup(@() fclose(fid));

% sc16 格式为 int16 I、int16 Q 交替存储；读取后归一化到约 [-1, 1]。
if strcmpi(fmt, 'sc16')
    raw = fread(fid, sampleCount(2 * maxComplex), 'int16=>double');
    raw = raw ./ 32768;
elseif strcmpi(fmt, 'fc32')
    raw = fread(fid, sampleCount(2 * maxComplex), 'single=>double');
else
    error('Unsupported capture format: %s', fmt);
end

if numel(raw) < 20000
    error('Too few raw samples in capture: %d', numel(raw));
end

% 将 I/Q 交织数据还原为复数基带信号，并去除直流分量。
rx = complex(raw(1:2:end), raw(2:2:end));
rx = rx - mean(rx);

% WLAN Toolbox 的 Non-HT 解析按 20 MHz 信道处理；非 20 MS/s 时重采样。
if abs(fs - 20e6) > 1
    rx20 = resample(rx, 20e6, fs);
else
    rx20 = rx;
end

% 幅度归一化，避免不同采集增益导致检测阈值差异过大。
rx20 = double(rx20(:));
peak = max(abs(rx20));
if peak > 0
    rx20 = rx20 ./ peak;
end

fprintf('complex_samples_20msps: %d\n', numel(rx20));

% CBW20 表示 20 MHz 信道带宽；ind0 保存 L-STF/L-LTF/L-SIG 等字段位置。
cbw = 'CBW20';
ind0 = wlanFieldIndices(wlanNonHTConfig);
pos = 1;
packets = 0;
lsigOk = 0;
results = struct('ssid', {}, 'bssid', {}, 'subtype', {}, 'start_sample', {}, ...
    'mcs', {}, 'psdu_length', {}, 'bit_order', {}, 'cfo_hz', {});
seen = {};
signalLength = numel(rx20);
lastProgressPercent = floor(100 * pos / signalLength);

% 打印初始解析进度，后续每前进到一个新的整数百分比再打印一次。
printDecodeProgress(pos, signalLength, packets);

while pos < signalLength - 6000 && packets < maxPackets
    currentPercent = floor(100 * pos / signalLength);
    if currentPercent > lastProgressPercent
        printDecodeProgress(pos, signalLength, packets);
        lastProgressPercent = currentPercent;
    end

    % 在当前位置之后搜索 WiFi 包前导码，找不到包时说明后面已无可解析包。
    pktOffset = wlanPacketDetect(rx20(pos:end), cbw);
    if isempty(pktOffset)
        break;
    end

    % pktStart 是当前包在整段采集信号中的起始采样点。
    pktStart = pos + pktOffset;
    if pktStart + ind0.LSIG(2) > numel(rx20)
        break;
    end

    try
        seg0 = rx20(pktStart:end);

        % 使用 L-STF 估计粗频偏，先把较大的载波频率偏差校正掉。
        lstf = seg0(ind0.LSTF(1):ind0.LSTF(2), :);
        coarse = wlanCoarseCFOEstimate(lstf, cbw);

        n = (0:numel(seg0)-1).';
        seg = seg0 .* exp(-1i * 2 * pi * coarse * n / 20e6);

        % 使用 L-LTF 估计细频偏，进一步提高后续 OFDM 解调的可靠性。
        lltf = seg(ind0.LLTF(1):ind0.LLTF(2), :);
        fine = wlanFineCFOEstimate(lltf, cbw);
        seg = seg .* exp(-1i * 2 * pi * fine * n / 20e6);

        % L-LTF 还用于估计信道响应，供 LSIG 和数据区均衡使用。
        lltf = seg(ind0.LLTF(1):ind0.LLTF(2), :);
        demodLLTF = wlanLLTFDemodulate(lltf, cbw);
        chEst = wlanLLTFChannelEstimate(demodLLTF, cbw);
        noiseVar = 1e-5;

        % LSIG 中包含速率和 PSDU 长度，是后续解调 Non-HT 数据区的关键。
        [bits, fail] = wlanLSIGRecover(seg(ind0.LSIG(1):ind0.LSIG(2), :), chEst, noiseVar, cbw);
        if ~fail
            lsigOk = lsigOk + 1;
            rateBits = bits(1:4).';
            lenBits = bits(6:17).';

            % 由于不同工具链的 bit 顺序可能不同，这里同时尝试 LSB/MSB 两种解释。
            lenList = unique([bitsToDecimalLsb(lenBits), bitsToDecimalMsb(lenBits)]);
            mcsList = unique([ratecode2mcs(bitsToDecimalLsb(rateBits)), ...
                ratecode2mcs(bitsToDecimalMsb(rateBits)), 0:7]);

            for lenTry = lenList
                if lenTry <= 0 || lenTry > 4095
                    continue;
                end

                for mcsTry = mcsList
                    if mcsTry < 0
                        continue;
                    end

                    % 根据候选 MCS 和长度构造 Non-HT 配置，并检查数据区是否越界。
                    cfg = wlanNonHTConfig('MCS', mcsTry, 'PSDULength', lenTry);
                    ind = wlanFieldIndices(cfg);
                    if ind.NonHTData(2) > numel(seg)
                        continue;
                    end

                    try
                        % 恢复 Non-HT Data 字段，得到 MAC 帧对应的 PSDU 比特。
                        recData = wlanNonHTDataRecover( ...
                            seg(ind.NonHTData(1):ind.NonHTData(2), :), chEst, noiseVar, cfg);

                        if numel(recData) < 8 * lenTry
                            continue;
                        end

                        for order = 1:2
                            % 把比特流重新组装成 MPDU 字节，并兼容两种常见 bit 顺序。
                            if order == 1
                                mpdu = bitsToBytes(recData(1:8*lenTry), true);
                                bitOrder = 'lsb_first';
                            else
                                mpdu = bitsToBytes(recData(1:8*lenTry), false);
                                bitOrder = 'msb_first';
                            end

                            % 从管理帧中解析 SSID 信息元素、BSSID 和帧子类型。
                            [ssid, bssid, subtype] = parseSsidLocal(mpdu);
                            if ~isempty(ssid)
                                key = [ssid '|' bssid];
                                if ~any(strcmp(seen, key))
                                    % 同一个 SSID/BSSID 只记录一次，避免 Beacon 重复出现。
                                    seen{end+1} = key; %#ok<AGROW>
                                    entry = struct( ...
                                        'ssid', ssid, ...
                                        'bssid', bssid, ...
                                        'subtype', subtype, ...
                                        'start_sample', pktStart, ...
                                        'mcs', mcsTry, ...
                                        'psdu_length', lenTry, ...
                                        'bit_order', bitOrder, ...
                                        'cfo_hz', coarse + fine);
                                    results(end+1) = entry; %#ok<AGROW>
                                    fprintf('SSID_FOUND ssid="%s" bssid=%s subtype=%s start=%d mcs=%d len=%d order=%s cfo=%.1f\n', ...
                                        ssid, bssid, subtype, pktStart, mcsTry, lenTry, bitOrder, coarse + fine);
                                end
                            end
                        end
                    catch
                    end
                end
            end
        end
    catch
    end

    packets = packets + 1;

    % 窗口向后移动。320 个采样点约等于一个短前导量级，可避免反复命中同一包头。
    pos = pktStart + 320;
end

% 循环结束时再打印一次最终扫描位置，便于判断是扫完还是中途无包退出。
printDecodeProgress(min(pos, signalLength), signalLength, packets);
fprintf('packets_checked=%d lsig_ok=%d\n', packets, lsigOk);
end


function printDecodeProgress(pos, signalLength, packets)
% 按“当前解析位置索引 / 全信号索引长度”计算并打印解析进度。
percent = 100 * double(pos) / double(signalLength);
fprintf('解析进度: 当前索引=%d / 全信号长度=%d, 进度=%.2f%%, 已检查包数=%d\n', ...
    pos, signalLength, percent, packets);
end


function count = sampleCount(n)
% fread 需要明确读取数量；inf 表示读取整个文件。
if isinf(n)
    count = inf;
else
    count = n;
end
end


function value = bitsToDecimalLsb(bits)
% 按低位在前解释 bit 序列。
bits = double(bits(:)).';
value = sum(bits .* 2.^(0:numel(bits)-1));
end


function value = bitsToDecimalMsb(bits)
% 按高位在前解释 bit 序列。
bits = double(bits(:)).';
value = sum(bits .* 2.^(numel(bits)-1:-1:0));
end


function bytes = bitsToBytes(bits, lsbFirst)
% 将解调得到的 0/1 比特流按 8 bit 一组打包为 MPDU 字节。
bits = double(bits(:));
nBytes = floor(numel(bits) / 8);
bits = reshape(bits(1:8*nBytes), 8, nBytes).';

if lsbFirst
    weights = 2.^(0:7);
else
    weights = 2.^(7:-1:0);
end

bytes = uint8(bits * weights(:)).';
end


function mcs = ratecode2mcs(code)
% LSIG rate code 到 Non-HT MCS 的映射，用于确定 OFDM 调制编码方式。
if code == bin2dec('1101'), mcs = 0; return; end
if code == bin2dec('1111'), mcs = 1; return; end
if code == bin2dec('0101'), mcs = 2; return; end
if code == bin2dec('0111'), mcs = 3; return; end
if code == bin2dec('1001'), mcs = 4; return; end
if code == bin2dec('1011'), mcs = 5; return; end
if code == bin2dec('0001'), mcs = 6; return; end
if code == bin2dec('0011'), mcs = 7; return; end
mcs = -1;
end


function [ssid, bssid, subtype] = parseSsidLocal(mpdu)
% 解析 802.11 管理帧。这里只关心 Beacon 和 Probe Response 中的 SSID 信息元素。
ssid = '';
bssid = '';
subtype = '';

if numel(mpdu) < 40
    return;
end

fc = double(mpdu(1)) + 256 * double(mpdu(2));
frameType = bitand(bitshift(fc, -2), 3);
frameSubtype = bitand(bitshift(fc, -4), 15);

% frameType=0 表示管理帧；subtype=8 是 Beacon，subtype=5 是 Probe Response。
if frameType ~= 0 || ~(frameSubtype == 8 || frameSubtype == 5)
    return;
end

if frameSubtype == 8
    subtype = 'beacon';
else
    subtype = 'probe_response';
end

bssid = sprintf('%02x:%02x:%02x:%02x:%02x:%02x', mpdu(17:22));

% Beacon / Probe Response 的固定参数为 12 字节，信息元素从 MPDU 第 37 字节开始。
pos = 37;
while pos + 1 <= numel(mpdu)
    eid = double(mpdu(pos));
    elen = double(mpdu(pos + 1));
    pos = pos + 2;

    if pos + elen - 1 > numel(mpdu)
        return;
    end

    if eid == 0 && elen <= 32
        % 信息元素 ID=0 表示 SSID；长度为 0 时是隐藏 SSID。
        if elen == 0
            ssid = '<hidden>';
        else
            bytes = mpdu(pos:pos+elen-1);
            ssid = decodeSsidBytes(bytes);
        end
        return;
    end

    pos = pos + elen;
end
end


function ssid = decodeSsidBytes(bytes)
% SSID 通常是 UTF-8；如果遇到非 UTF-8 字节，则退回为普通 char 转换。
try
    ssid = char(native2unicode(bytes(:).', 'UTF-8'));
catch
    ssid = char(bytes(:).');
end
end


function writeResultsExcel(results, captureFile, outputFile)
% 将解析得到的 WiFi 扫描结果写入 Excel 文件。
% 如果没有解析到 SSID，也会生成 output.xlsx，并在表格中写明未解析到结果。

headers = {'序号', 'SSID名称', 'BSSID', '帧类型', '起始采样点', ...
    'MCS', 'PSDU长度', '比特顺序', '频偏Hz', '采集数据文件'};

if isempty(results)
    rows = {[], '未解析到WiFi名称', '', '', '', '', '', '', '', char(captureFile)};
else
    rows = cell(numel(results), numel(headers));
    for k = 1:numel(results)
        rows{k, 1} = k;
        rows{k, 2} = results(k).ssid;
        rows{k, 3} = results(k).bssid;
        rows{k, 4} = results(k).subtype;
        rows{k, 5} = results(k).start_sample;
        rows{k, 6} = results(k).mcs;
        rows{k, 7} = results(k).psdu_length;
        rows{k, 8} = results(k).bit_order;
        rows{k, 9} = results(k).cfo_hz;
        rows{k, 10} = char(captureFile);
    end
end

excelContent = [headers; rows];

% 新版 MATLAB 推荐 writecell；如果版本较旧，则退回到 xlswrite。
try
    if exist('writecell', 'file') == 2
        writecell(excelContent, outputFile);
    else
        xlswrite(outputFile, excelContent);
    end
catch firstError
    try
        xlswrite(outputFile, excelContent);
    catch secondError
        error('Failed to write Excel file: %s\nFirst error: %s\nSecond error: %s', ...
            outputFile, firstError.message, secondError.message);
    end
end
end
