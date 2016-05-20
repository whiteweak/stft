close all; clear all;

% Closed form LCMV BF from Springer (eq 47.7)
% W_LCMV(k,l) = (Z(k,l)Z^H(k,l))^-1 A(k) / (A^H(k)(Z(k,l)Z^H(k,l))^-1 A(k))

% Import audio files
[s1,Fs1] = audioread('50_male_speech_english_ch10_orth_2Y.flac'); % s = source, Fs1 = sampling frequency
[s2,Fs2] = audioread('44_soprano_ch17_orth_1Z.flac'); % ns = noise stationary, Fs2 = sampling frequency

% Shorten the signals
NSig = 2^15; % Truncate signals to be a y*0.5 multiple of the window length, where y is an integer.
start = 29500;
s1 = s1(start:NSig-1+start); s2 = s2(start:NSig-1+start);
s3 = randn(NSig,1);

% Normalize the three signals to have a maximum amplitude just less than 1
s1 = myNormalize(s1); s2 = myNormalize(s2); s3 = myNormalize(s3);

%% STFT
K = 2^8+1; % Window length in samples. +1 makes the window length odd and symmetric. stft() will either truncate the window by 1, or overlap the 1st and last elements (which are both zero). This means we could consider the window length to be K-1 also depending on whether we would prefer to consider a symmetric or periodic window.
s1 = [zeros((K-1)/2,1);s1;zeros((K-1)/2,1)];
[S1,L] = stft(s1,K);
S2 = stft(s2,K);
% mySpectrogram(S1);

%% Recreate signal
% sHat = myOverlapAdd(S1);

% Reconstructed source signal vs original source
% figure; plot(s1,'.'); hold on; plot(sHat,'o'); legend('s1','sHat');

%% Springer BF
% Place sensors and sources, note that s3 is diffuse noise so has no
% location
zPos = [3,1,1 ; 4,1,1 ; 5,1,1 ; 6,1,1 ; 3.1,2,1 ; 4.1,2,1 ; 5.3,2,1 ; 6.4,2,1]'; 
sPos = [5,3.5,1 ; 2,4.5,1]';
% figure; plot(zPos(1,:),zPos(2,:),'o'); hold on; plot(sPos(1,:),sPos(2,:),'o'); xlim([0 10]); ylim([0 5]); legend('Sensors','Sources');

z = myObservInterp(zPos,sPos,s1,s2,s3);