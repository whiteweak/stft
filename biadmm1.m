%% Start again mvdr beamformer, hopefully distributed using biadmm. Needs 
% to have 50 sensors randomly placed within a 100x100x100 m free space. One
% target speech signal, and one noise signal, also randomly placed. Signal
% of interest is a 20 s speech signal chosen randomly from a 60 s file. fs
% = 16 kHz. Window length is 25 ms with a Hann window and 50% overlap.
% Interference is a randomly placed, zero meaqn gaussian point source with
% power equal to -5, 0, 5 dB when compared to the target signal. 
close all; clear;

% Import target audio
[s1,fs1] = audioread('273177__xserra__la-vaca-cega-eva.wav'); 

% Downsample
fsd = 16e3; % fsd = desired sampling frequency
fs = fs1/round(fs1/fsd); % fs = actual sampling frequency post resample
s1 = resample(s1,1,round(fs1/fsd));

% Truncate to desired length, ensure that the length is a multiple of 
% the window length, and randomly select a section of the audio file.
K = 2^9+1; % K = window length in samples, and the number of frequency bins
tls = 20; % tls = target length in seconds
tl = tls*fs-mod(tls*fs,K-1); % tl = target length in samples, adjusted for window length and sampling frequency
start = floor((length(s1)-tl)*rand);
s1 = s1(start:start+tl-1,1); % Truncate s1 to be one channel, and 20 s long

% Normalize the target audio file to make it easy to change files
s1rms = rms(s1);
s1rmsinv = 1./s1rms;
s1 = s1 * (0.1*diag(s1rmsinv));% This should probably be scaled down to avoid clipping

% Set up interferer with equal power, i.e. snr = 0 dB 
s1Pow = (s1'*s1) / length(s1);
s2 = sqrt(s1Pow) *  randn(length(s1),1); % Currently set up for equal power
s2Pow = (s2'*s2) / length(s2);
SourceSNRdB = 10*log10(s1Pow/s2Pow)

%% STFT 
% pad the source signals so the 1st half window doesn't distort the data
s1Padded = [zeros((K-1)/2,1);s1;zeros((K-1)/2,1)];
s2Padded = [zeros((K-1)/2,1);s2;zeros((K-1)/2,1)];

% Take stft of both sources and truncate to exclude negative frequencies
% as well as dc and fs/2.
[S1,L] = stft(s1Padded,K);
S1half = S1(2:(K+1)/2-1,:);
[S2,L2] = stft(s2Padded,K);
S2half = S2(2:(K+1)/2-1,:);

%% Place sensors
M = 20; % M = number of sensors
Nsrcs = 2; % Nsrcs = number of sources
spSize = 30;
space = [spSize, spSize, spSize]'; % Dimensions of the space
spcDim = length(space);
Mloc = (rand(M,spcDim)*diag(space)).'; % Mloc = matrix containing 3d sensor locations
sloc = ((rand(Nsrcs,spcDim)*diag(space))).';%+[0,0,2;0,0,2]).'; % sloc = matrix condaining 3d source locations

% Calculate distances
ssd = zeros(Nsrcs,M);
for ns=1:Nsrcs
    for m=1:M
        ssd(ns,m) = norm(Mloc(:,m)-sloc(:,ns));
    end
end

% Display layout
figure; plot3(Mloc(1,:), Mloc(2,:), Mloc(3,:), '*'); grid on; hold on; 
plot3(sloc(1,1), sloc(2,1), sloc(3,1), 'o'); 
plot3(sloc(1,2), sloc(2,2), sloc(3,2), '^'); legend('Sensors','Target','Interferer')
set(gca, 'fontsize', 14);

%% Create ATFs
Khalf = (K-1)/2-1;
fdom = (fs/(K-1)) * [1:Khalf]';
c = 343; % c = speed of sound in m.s^-1
At = zeros(Khalf,M);
Ai = zeros(Khalf,M);
Atnogain = zeros(Khalf,M);
for m=1:M
    At(:,m) = exp(-1i*2*pi*fdom'*ssd(1,m)/c) / (4*pi*ssd(1,m)^2);
    Ai(:,m) = exp(-1i*2*pi*fdom'*ssd(2,m)/c) / (4*pi*ssd(2,m)^2);
    Atnogain(:,m) = exp(-1i*2*pi*fdom'*ssd(1,m)/c); 
end

%% Create observations
X = zeros(Khalf,L,M); Xt = zeros(Khalf,L,M); Xi = zeros(Khalf,L,M);
for l = 1:L
    for m = 1:M
        Xt(:,l,m) = At(:,m).*S1half(:,l); % These are used for calculating SNR 
        Xi(:,l,m) = Ai(:,m).*S2half(:,l); % These are used for calculating SNR 
        X(:,l,m) = Xt(:,l,m)+Xi(:,l,m);
    end
end

%% Delay and sum
% W = Atnogain;
% [yds,ydsSNRdb] = myBfOp(X,Xt,Xi,W);
% ydsSNRdb

%% MVDR optimum weights
% dl = 1e-9; % dl = diagonal loading factor - ensures that the covariance is invertible
% Wopt = myMvdrOpt(At,X,dl);
% [yopt,yoptSNRdb] = myBfOp(X,Xt,Xi,Wopt);
% yoptSNRdb

%% Adaptive Frost MVDR
% mu = 200; % mu = step size 
% Iter = 10; % Iter = number of iterations per window
% [Y,W,Wmse] = myFrostAdapt(At,X,mu,Iter,Wopt);
% 
% % Create two sided Y and take istft
% Y = [zeros(1,L);Y;zeros(2,L);conj(flipud(Y))];
% yFrO = myOverlapAdd(Y); % yFrO = y Frost Online
% figure; plot(yFrO);% 
% figure; semilogy(Wmse);
% figure; plot(Wmse);

%% Adaptive Frost using actual covariance
% mu = 1000; % mu = step size 
% Iter = 10; % Iter = number of iterations per window
% [Y,W,Wmse] = myFrostAdaptTrueCov(At,X,mu,Iter,Wopt);
% 
% % Create two sided Y and take istft
% Y = [zeros(1,L);Y;zeros(2,L);conj(flipud(Y))];
% yFrO = myOverlapAdd(Y); % yFrO = y Frost Online
% figure; plot(yFrO);
% figure; semilogy(Wmse);
% figure; plot(Wmse);

%% Sparse distributed BiADMM MVDR
% Calculate the adjacency matrix
% Find sensor to sensor distances
sensd = zeros(M,M);
for m=1:M
    for mm=m:M
        sensd(m,mm) = norm(Mloc(:,m)-Mloc(:,mm));
    end
end
sensd = sensd + triu(sensd,1).';

sensdtmp = sensd + diag(ones(1,M)*2*spSize); % 2* spSize is guaranteed to be larger than any distance between sensors
Nnghbrs = 3; % Nnghbrs sets the number of neighbors per node
N = zeros(Nnghbrs,M); % N = matrix containing indices of the three closest neighbours to each node
for aaa = 1:3
    [sensdmin, sensdmini] = min(sensdtmp);
    N(aaa,:) = sensdmini;
    for bbb = 1:20
        sensdtmp(sensdmini(bbb),bbb) = 2*spSize;
        sensdtmp(bbb,sensdmini(bbb)) = 2*spSize;
    end
end
% if max(min(sensdtmp)) > dmax
%     display('Warning: not all nodes have neighbors.');
% end
% 
% C = (sensdtmp<dmax)
% sum(C,1)