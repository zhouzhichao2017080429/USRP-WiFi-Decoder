function results = decode_usrp_wifi_auto_english()
%DECODE_USRP_WIFI_AUTO_ENGLISH Decode WiFi SSID/BSSID from USRP B210 IQ captures.
%
% Author: zhouzhichao
% Date: 2026-06-12
%
% Description:
%   This program reads a USRP B210 WiFi electromagnetic signal capture from
%   the same folder. The capture is an sc16 interleaved IQ binary file. The
%   program uses MATLAB WLAN Toolbox to perform 802.11 non-HT OFDM packet
%   detection, frequency offset correction, channel estimation, LSIG parsing,
%   and non-HT data demodulation. It extracts the WiFi SSID, access point
%   BSSID, frame type, start sample, and related metadata from Beacon and
%   Probe Response management frames.
%
% Workflow:
%   1. Automatically locate the folder containing this .m file.
%   2. Prefer the ch36 USRP capture in the same folder.
%   3. Convert the sc16 interleaved I/Q data into a complex baseband signal.
%   4. Run packet detection, coarse/fine frequency offset correction, and
%      L-LTF channel estimation.
%   5. Parse LSIG to obtain candidate length and rate values, then try
%      non-HT demodulation.
%   6. Convert the demodulated bits to MPDU bytes and parse SSID/BSSID.
%   7. Print the scan progress as current parse position / total signal
%      length.
%   8. Print the decoded results and save the result structure to the MATLAB
%      base workspace variable wifi_ssid_results.
%   9. Export the scan results to output.xlsx in the same folder.
%
% Stop conditions:
%   The scan stops when it reaches the end of the capture, no later WiFi
%   packet is detected, a packet length exceeds the available signal, or the
%   maxPackets limit is reached. Before returning, the program prints SUMMARY,
%   reports the number of unique decoded SSID/BSSID entries, and generates
%   output.xlsx.
%
% Usage in MATLAB:
%   cd('D:\path\to\USRP+MATLAB+Python\auto code')
%   results = decode_usrp_wifi_auto_english;
%
% Note: before running, this folder only needs this script and one sc16 IQ
%       .bin capture file. The program automatically generates output.xlsx.

clc;

% Get the folder containing this script so it can run directly in auto code.
scriptDir = fileparts(mfilename('fullpath'));

% Prefer this ch36 capture because it previously produced the most AP results.
preferredCapture = 'usrp_wifi_20260611_ch36_20Msps_sc16_fs20Msps_dur0p479355s.bin';
captureFile = fullfile(scriptDir, preferredCapture);

% If the preferred file does not exist, read the first .bin file in this folder.
if exist(captureFile, 'file') ~= 2
    files = dir(fullfile(scriptDir, '*.bin'));
    if isempty(files)
        error('No .bin USRP IQ capture was found in the script folder.');
    end
    captureFile = fullfile(files(1).folder, files(1).name);
end

% USRP capture parameters: 20 MS/s; sc16 means interleaved int16 I/Q samples.
sampleRate = 20e6;
captureFormat = 'sc16';
maxComplexSamples = inf;
maxPackets = inf;

fprintf('USRP B210 WiFi SSID decode\n');
fprintf('capture: %s\n', getFileNameOnly(captureFile));
fprintf('format: %s\n', captureFormat);
fprintf('sample_rate: %.0f Hz\n\n', sampleRate);

% Main parser: read IQ, perform WiFi PHY/MAC parsing, and return unique SSID/BSSID entries.
results = decodeCapture(captureFile, sampleRate, captureFormat, maxComplexSamples, maxPackets);

% Save parsed results to output.xlsx for later review and organization.
outputFile = fullfile(scriptDir, 'output.xlsx');
writeResultsExcel(results, captureFile, outputFile);

% Print a final command-line summary of decoded WiFi AP entries.
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

% Put the results in the MATLAB base workspace for manual review or analysis.
assignin('base', 'wifi_ssid_results', results);
fprintf('\nResult struct was also assigned to workspace variable: wifi_ssid_results\n');
fprintf('Excel output was saved to: %s\n', getFileNameOnly(outputFile));
end


function results = decodeCapture(infile, fs, fmt, maxComplex, maxPackets)
% Read the USRP IQ file and use WLAN Toolbox to parse 802.11 OFDM packets offline.

fid = fopen(infile, 'rb');
if fid < 0
    error('Cannot open capture file: %s', getFileNameOnly(infile));
end
fileCleanup = onCleanup(@() fclose(fid));

% sc16 stores alternating int16 I and int16 Q samples; normalize to about [-1, 1].
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

% Convert interleaved I/Q data to a complex baseband signal and remove DC offset.
rx = complex(raw(1:2:end), raw(2:2:end));
rx = rx - mean(rx);

% WLAN Toolbox non-HT parsing assumes a 20 MHz channel; resample if not 20 MS/s.
if abs(fs - 20e6) > 1
    rx20 = resample(rx, 20e6, fs);
else
    rx20 = rx;
end

% Normalize amplitude to reduce threshold variation caused by different capture gains.
rx20 = double(rx20(:));
peak = max(abs(rx20));
if peak > 0
    rx20 = rx20 ./ peak;
end

fprintf('complex_samples_20msps: %d\n', numel(rx20));

% CBW20 denotes 20 MHz channel bandwidth; ind0 stores L-STF/L-LTF/L-SIG field indices.
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

% Print initial progress, then print again whenever a new integer percent is reached.
printDecodeProgress(pos, signalLength, packets);

while pos < signalLength - 6000 && packets < maxPackets
    currentPercent = floor(100 * pos / signalLength);
    if currentPercent > lastProgressPercent
        printDecodeProgress(pos, signalLength, packets);
        lastProgressPercent = currentPercent;
    end

    % Search for a WiFi packet preamble after the current position.
    pktOffset = wlanPacketDetect(rx20(pos:end), cbw);
    if isempty(pktOffset)
        break;
    end

    % pktStart is the start sample of the current packet in the full capture.
    pktStart = pos + pktOffset;
    if pktStart + ind0.LSIG(2) > numel(rx20)
        break;
    end

    try
        seg0 = rx20(pktStart:end);

        % Estimate coarse CFO from L-STF and correct large carrier offset first.
        lstf = seg0(ind0.LSTF(1):ind0.LSTF(2), :);
        coarse = wlanCoarseCFOEstimate(lstf, cbw);

        n = (0:numel(seg0)-1).';
        seg = seg0 .* exp(-1i * 2 * pi * coarse * n / 20e6);

        % Estimate fine CFO from L-LTF to improve later OFDM demodulation.
        lltf = seg(ind0.LLTF(1):ind0.LLTF(2), :);
        fine = wlanFineCFOEstimate(lltf, cbw);
        seg = seg .* exp(-1i * 2 * pi * fine * n / 20e6);

        % L-LTF is also used to estimate channel response for LSIG and data equalization.
        lltf = seg(ind0.LLTF(1):ind0.LLTF(2), :);
        demodLLTF = wlanLLTFDemodulate(lltf, cbw);
        chEst = wlanLLTFChannelEstimate(demodLLTF, cbw);
        noiseVar = 1e-5;

        % LSIG contains the rate and PSDU length needed for non-HT data recovery.
        [bits, fail] = wlanLSIGRecover(seg(ind0.LSIG(1):ind0.LSIG(2), :), chEst, noiseVar, cbw);
        if ~fail
            lsigOk = lsigOk + 1;
            rateBits = bits(1:4).';
            lenBits = bits(6:17).';

            % Try both LSB/MSB interpretations because bit order can differ by toolchain.
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

                    % Build a non-HT config from candidate MCS/length and check bounds.
                    cfg = wlanNonHTConfig('MCS', mcsTry, 'PSDULength', lenTry);
                    ind = wlanFieldIndices(cfg);
                    if ind.NonHTData(2) > numel(seg)
                        continue;
                    end

                    try
                        % Recover the non-HT Data field to obtain PSDU bits for the MAC frame.
                        recData = wlanNonHTDataRecover( ...
                            seg(ind.NonHTData(1):ind.NonHTData(2), :), chEst, noiseVar, cfg);

                        if numel(recData) < 8 * lenTry
                            continue;
                        end

                        for order = 1:2
                            % Repack the bitstream into MPDU bytes using both common bit orders.
                            if order == 1
                                mpdu = bitsToBytes(recData(1:8*lenTry), true);
                                bitOrder = 'lsb_first';
                            else
                                mpdu = bitsToBytes(recData(1:8*lenTry), false);
                                bitOrder = 'msb_first';
                            end

                            % Parse SSID information element, BSSID, and frame subtype.
                            [ssid, bssid, subtype] = parseSsidLocal(mpdu);
                            if ~isempty(ssid)
                                key = [ssid '|' bssid];
                                if ~any(strcmp(seen, key))
                                    % Record each SSID/BSSID only once to avoid repeated beacons.
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

    % Move the search window forward by about one short preamble to avoid duplicate hits.
    pos = pktStart + 320;
end

% Print the final scan position to show whether the scan ended or stopped early.
printDecodeProgress(min(pos, signalLength), signalLength, packets);
fprintf('packets_checked=%d lsig_ok=%d\n', packets, lsigOk);
end


function printDecodeProgress(pos, signalLength, packets)
% Compute and print progress as current parse index / total signal length.
percent = 100 * double(pos) / double(signalLength);
fprintf('Decode progress: current_index=%d / signal_length=%d, progress=%.2f%%, packets_checked=%d\n', ...
    pos, signalLength, percent, packets);
end


function count = sampleCount(n)
% fread requires an explicit count; inf means read the full file.
if isinf(n)
    count = inf;
else
    count = n;
end
end


function value = bitsToDecimalLsb(bits)
% Interpret the bit sequence as LSB first.
bits = double(bits(:)).';
value = sum(bits .* 2.^(0:numel(bits)-1));
end


function value = bitsToDecimalMsb(bits)
% Interpret the bit sequence as MSB first.
bits = double(bits(:)).';
value = sum(bits .* 2.^(numel(bits)-1:-1:0));
end


function bytes = bitsToBytes(bits, lsbFirst)
% Pack the demodulated 0/1 bitstream into MPDU bytes, 8 bits per byte.
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
% Map LSIG rate code to non-HT MCS to determine the OFDM modulation/coding mode.
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
% Parse 802.11 management frames; only Beacon and Probe Response SSID elements are used.
ssid = '';
bssid = '';
subtype = '';

if numel(mpdu) < 40
    return;
end

fc = double(mpdu(1)) + 256 * double(mpdu(2));
frameType = bitand(bitshift(fc, -2), 3);
frameSubtype = bitand(bitshift(fc, -4), 15);

% frameType=0 means management frame; subtype=8 is Beacon and subtype=5 is Probe Response.
if frameType ~= 0 || ~(frameSubtype == 8 || frameSubtype == 5)
    return;
end

if frameSubtype == 8
    subtype = 'beacon';
else
    subtype = 'probe_response';
end

bssid = sprintf('%02x:%02x:%02x:%02x:%02x:%02x', mpdu(17:22));

% Beacon / Probe Response fixed parameters are 12 bytes; information elements start at byte 37.
pos = 37;
while pos + 1 <= numel(mpdu)
    eid = double(mpdu(pos));
    elen = double(mpdu(pos + 1));
    pos = pos + 2;

    if pos + elen - 1 > numel(mpdu)
        return;
    end

    if eid == 0 && elen <= 32
        % Information element ID 0 is SSID; zero length means hidden SSID.
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
% SSID is usually UTF-8; fall back to plain char conversion for non-UTF-8 bytes.
try
    ssid = char(native2unicode(bytes(:).', 'UTF-8'));
catch
    ssid = char(bytes(:).');
end
end


function writeResultsExcel(results, captureFile, outputFile)
% Write decoded WiFi scan results to an Excel file.
% If no SSID is decoded, output.xlsx is still generated with a no-result row.

headers = {'Index', 'SSID', 'BSSID', 'Frame Type', 'Start Sample', ...
    'MCS', 'PSDU Length', 'Bit Order', 'Frequency Offset Hz', 'Capture File'};
captureDisplayName = char(string(getFileNameOnly(captureFile)));

if isempty(results)
    rows = {[], 'No WiFi SSID decoded', '', '', '', '', '', '', '', captureDisplayName};
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
        rows{k, 10} = captureDisplayName;
    end
end

excelContent = [headers; rows];

% Prefer writecell in newer MATLAB versions; fall back to xlswrite for older versions.
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


function name = getFileNameOnly(filePath)
% Return the file name and extension without the parent directory.
[~, stem, ext] = fileparts(filePath);
name = [stem ext];
end
