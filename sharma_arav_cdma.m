clear;
close all;
clc;

% Arav Sharma - CDMA Assignment

% FINAL MESSAGE:

% "Interference reconstruction module and interference canceller perform 
% the soft cancellation, spatial filter module performs the soft spatial 
% filtering, and APP calculator performs the demapping."

load Rcvd_Sharma.mat;

B_RCOS = [0.0038, 0.0052, -0.0044, -0.0121, -0.0023, 0.0143, 0.0044, -0.0385, -0.0563, ...
          0.0363, 0.2554, 0.4968, 0.6025, 0.4968, 0.2554, 0.0363, -0.0563, -0.0385, ...
          0.0044, 0.0143, -0.0023, -0.0121, -0.0044, 0.0052, 0.0038];


% here we filter the signal and downsample it at the same time

rcvd_filt = upfirdn(Rcvd, B_RCOS, 1, 4);

figure();
plot(abs(rcvd_filt));
title('Absolute Value of Filtered Received Signal');
xlabel('Sample Index');
ylabel('|rcvd\_filt|');

% here we account for the ramp up of the filter to detect the start of the
% signal. We wait until the energy in the signal goes to one

threshold = 0.95;
start_index = find(abs(rcvd_filt) > threshold, 1, 'first');
hold on;
plot(start_index, abs(rcvd_filt(start_index)), 'ro');
legend('|rcvd_filt|', 'Detected Frame Start', 'Interpreter', 'none');
fprintf('Approximate frame start from abs threshold: %d\n', start_index);

% we cut ramp-up off off the signal
rcvd_filt = rcvd_filt(start_index:end);

% we divide the signal into frames of 255 samples
frames = reshape(rcvd_filt, 255, []);

% we generate m sequences with all possible initial states
all_m_seqs = gen_all_m_seqs();

corrs = zeros(1, 255);

% correlate each m sequence with the pilot (1st frame) to determine the
% initial state of LFSR used in the transmitter
y = frames(:,1); % pilot (1st frame)
for n = 1:255
    champ = all_m_seqs{1,n}; % each index has a different initial state
    z = pskmod(champ, 2)'; % bpsk modulate the given m sequence
    corrs(n) = max(corr(z, y)); % max correlation between m sequence and pilot
end

% the index of m sequence with the best correlation to the pilot is the
% correct initial state. You can verify this was chosen correctly by also
% correlating it with any of the other frames and you should get the same
% result
[~, idx] = max(corrs);

disp("inital state of the LFSR (index):");
disp(idx);
pn_seq_bpsk = pskmod(all_m_seqs{1,idx}, 2)';

% superimposing pn sequence and pilot to show correlation
figure();
plot(0:254, real(y));
hold on;
plot(0:254, real(pn_seq_bpsk));
hold off;
title('Pilot and best PN Sequence');
xlabel('Sample Index');
legend('Pilot', 'PN Sequence');

% denoise all of the frames by dividing them by the pn sequence
denoised = frames ./ pn_seq_bpsk;

walsh = hadamard(8); % generate the hadamard matrix

% plot denoised frames. The 3 characters and useless data at the end of the
% frames can be clearly seen in these plots
figure();
plot(0:254, real(denoised));
title('Denoised Frames');
xlabel('Sample Index');

% crop the denoised data to remove the useless data at the end of the
% frames
denoised = denoised(1:192, :);

figure();
plot(0:191, real(denoised));
title('Cropped Frames');
xlabel('Sample Index');

denoised_size = size(denoised);
num_frames = denoised_size(2); % get the number of frames after reshaping

fprintf("Decoded message: ");

for n = 2:num_frames %decode all of the frames (besides pilot)
    % here we multiply the frame by the conjugate of the pilot to remove
    % the frequency offset, which destroys the orthogonality of the walsh
    % coding
    data = denoised(:, n) .* conj(denoised(:,1));
    chars = reshape(data, 64, 3); % reshape to isolate each character (64 chips)

    for m = 1:3
        c = reshape(chars(:,m), 8, 8); % take blocks of 8 chips for decoding
        x = c' * walsh; % decode!
        x = x ./ x(:, 1); % divide by local pilot to remove phase offset
        chan5 = x(:,6); % walsh channel 5 contains the data
        bits = pskdemod(chan5, 2); % demodulate the data
        ascii_val = bit2int(bits, 8, false);
        letter = char(ascii_val);
        fprintf(letter);
    end
end
fprintf("\n");

% Below is an example of what is going on in this loop to create graphs

data = denoised(:, 2) .* conj(denoised(:,1));
chars = reshape(data, 64, 3);
c = reshape(chars(:,1), 8, 8);

figure();
plot(0:191, real(data));
hold on;
plot(0:63, real(chars(:,1)));
plot(0:7, real(c(:,1)));
hold off;
title('2nd Frame (cropped to 192 samples)');
xlabel('Sample Index');
legend('All data', '1 character', '8 chips');

figure();
imagesc(abs(c));
title('coded data');

x = c' * walsh;

figure();
imagesc(abs(x));
title('decoded data (pilot and data channel clearly shown)');

figure();
plot(x, 'o');
title('rotated data');

x = x ./ x(:, 1);
figure();
plot(x, 'o');
title('derotated data');


% EXTRA CREDIT: FREQUENCY OFFSET
% frequency offset is the rate of change of the phase offset
% we can use the chip rate to calculate this in Hz

y = frames(:,1) ./ pn_seq_bpsk; % denoised pilot
denoised = frames(:, 2:end) ./ pn_seq_bpsk; % remove PN sequence

%average phase across chips within each frame
avg_phase_per_frame = mean(angle(denoised .* conj(y)), 1);

% unwrap the phased across the frames
avg_phase_unwrapped = unwrap(avg_phase_per_frame);

% the slope of the best fit like will be the frequency offset
frame_idx = 0:65;
p = polyfit(frame_idx, avg_phase_unwrapped, 1);  % mx + b

Tc = 1e-6; % chip duration derived from chip rate
Tf = 255 * Tc; % duration of a frame

freq_offset = p(1) / (2*pi*Tf); 
fprintf('Estimated constant frequency offset: %.2f Hz\n', freq_offset);
figure;
plot(frame_idx, avg_phase_unwrapped, 'bo-'); 
hold on;
plot(frame_idx, polyval(p, frame_idx), 'r--');
xlabel('Frame Index');
ylabel('Unwrapped Avg Phase (radians)');
title('Phase Drift Across Frames');
legend('Unwrapped Phase', 'Linear Fit');

function all_m_seqs = gen_all_m_seqs()
    taps = [8 7 6 1];
    order = max(taps);
    num_states = 2^order - 1;  % total number of possible states
    all_m_seqs = cell(1, num_states);  % store all possible m seqs
    
    % generate all non-zero initial states
    idx = 1;
    for i = 1:(2^order - 1)
        init = de2bi(i, order, 'left-msb');
        m_seq = gen_m_seq(init);
        all_m_seqs{idx} = m_seq;
        idx = idx + 1;
    end
    fprintf('Generated %d m-sequences from all non-zero initial states.\n', num_states);

    % verify unique m sequences
    unique_seqs = unique(cellfun(@(x) num2str(x), all_m_seqs, 'UniformOutput', false));
    fprintf('Number of unique m-sequences: %d\n', length(unique_seqs));
end


function m_seq = gen_m_seq(init)
    taps = [8 7 6 1]; % provided LFSR taps
    order = max(taps);
    seq_length = 2^order - 1;
    reg = init; % initial state (decimal value)
    m_seq = zeros(1, seq_length);
    
    for i = 1:seq_length
        m_seq(i) = reg(order);
        feedback = 0;
        for j = 1:length(taps)
            % apply feedback at the taps
            feedback = xor(feedback, reg(order - taps(j) + 1));
        end
        reg = [feedback reg(1:order-1)]; % update register
    end
end