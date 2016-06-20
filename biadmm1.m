%% Start again mvdr beamformer, hopefully distributed using biadmm. Needs 
% to have 50 sensors randomly placed within a 100x100x100 m free space. One
% target speech signal, and one noise signal, also randomly placed. Signal
% of interest is a 20 s speech signal chosen randomly from a 60 s file. fs
% = 16 kHz. Window length is 25 ms with a Hann window and 50% overlap.
% Interference is a randomly placed, zero meaqn gaussian point source with
% power equal to -5, 0, 5 dB when compared to the target signal. 
% 
% Based on Matt's paper.
close all; 

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
space = [30, 30, 30]'; % Dimensions of the space
spcDim = length(space);
Mloc = (rand(M,spcDim)*diag(space)).'; % Mloc = matrix containing 3d sensor locations
sloc = ((rand(Nsrcs,spcDim)*diag(space))).';%+[0,0,2;0,0,2]).'; % sloc = matrix condaining 3d source locations

% Display layout
figure; plot3(Mloc(1,:), Mloc(2,:), Mloc(3,:), '*'); grid on; hold on; 
plot3(sloc(1,1), sloc(2,1), sloc(3,1), 'o'); 
plot3(sloc(1,2), sloc(2,2), sloc(3,2), '^'); legend('Sensors','Target','Interferer')
set(gca, 'fontsize', 14);

% Calculate distances
ssd = zeros(spcDim,M,Nsrcs);
for ns = 1:Nsrcs
    for m = 1:M
        ssd(ns,m) = norm(Mloc(:,m)-sloc(:,ns));
    end    
end

% Find closest sensors
% [distmin,distmini] = min(dist);

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

% Check sensors closest to each source
% Xt = [zeros(1,L);X(:,:,distmini(1));zeros(2,L);conj(flipud(X(:,:,distmini(1))))];
% xt = myOverlapAdd(Xt);
% Xi = [zeros(1,L);X(:,:,distmini(2));zeros(2,L);conj(flipud(X(:,:,distmini(2))))];
% xi = myOverlapAdd(Xi);

%% Delay and sum
W = Atnogain;
[yds,ydsSNRdb] = myBfOp(X,Xt,Xi,W);
ydsSNRdb

%% MVDR optimum weights
W = ones(Khalf,M);
for k=1:Khalf
    R = zeros(M,M); % R is the spatial covariance of the inputs
    for l=1:L
        Xtmp = squeeze(X(k,l,:));
        R = R + Xtmp*Xtmp'; % Sum the covariance over l
    end
    R = R + 1e-9*eye(M); % Diagonal loading
    Ak = At(k,:).';
    W(k,:) = (R\Ak)/(Ak'*(R\Ak)); % Calculate optimum weights vector 
end
Wopt = W;
[yopt,yoptSNRdb] = myBfOp(X,Xt,Xi,W);
yoptSNRdb

%% Adaptive Frost using actual covariance
R = zeros(M,M);
for l=1:L
    R = R + squeeze(X(:,l,:)).'*squeeze(conj(X(:,l,:)));
end

%% Adaptive Frost MVDR
P = zeros(Khalf,M,M); 
F = zeros(Khalf,M);
for k = 1:Khalf
    Ak = At(k,:).';
    P(k,:,:) = eye(M) - (Ak*Ak')/(norm(Ak)^2);
    F(k,:) = Ak/(norm(Ak)^2);
end
% W = F; % Initialize weight vector
% % Iterate
% mu = 200; % mu = step size 
% Iter = 10;
% Y = zeros(Khalf,L);
Wmse = zeros(L,1);
% for l=1:L
%     Xtmp = squeeze(X(:,l,:));
%     Y(:,l) = sum(conj(W).*Xtmp,2);     
%     for k = 1:Khalf
%         Xtmp = squeeze(X(k,l,:));
%         Rtmp = Xtmp*Xtmp';
%         Ptmp = squeeze(P(k,:,:));
%         Ftmp = F(k,:).';
%         for iter = 1:Iter
%             Wtmp = W(k,:).'; 
%             W(k,:) = Ptmp*(Wtmp-mu*Rtmp*Wtmp)+Ftmp; % Update weights
%         end
%     end
%     Wmse(l) = myMse(Wopt,W);
% end
% 
% % Create two sided Y and take istft
% Y = [zeros(1,L);Y;zeros(2,L);conj(flipud(Y))];
% yFrO = myOverlapAdd(Y); % yFrO = y Frost Online
% figure; plot(yFrO);
% 
% figure; semilogy(Wmse);
% figure; plot(Wmse);

%% Adaptive Frost using actual covariance
% R = zeros(Khalf,M,M);
% for l=1:L
%     for k=1:Khalf
%         R(k,:,:) = squeeze(R(k,:,:)) + (1/L)*squeeze(X(k,l,:))*squeeze((X(k,l,:)))';
%     end
% end
% 
% mu = 1000; % mu = step size 
% Iter = 10;
% Y = zeros(Khalf,L);
% W = ones(Khalf,M);
% for l=1:L
%     Xtmp = squeeze(X(:,l,:));
%     Y(:,l) = sum(conj(W).*Xtmp,2);     
%     for k = 1:Khalf
%         Xtmp = squeeze(X(k,l,:));
%         Ptmp = squeeze(P(k,:,:));
%         Ftmp = F(k,:).';
%         Rtmp = squeeze(R(k,:,:));
%         for iter = 1:Iter
%             Wtmp = W(k,:).'; 
%             W(k,:) = Ptmp*(Wtmp-mu*Rtmp*Wtmp)+Ftmp; % Update weights
%         end
%     end
%     Wmse(l) = myMse(Wopt,W);
% end
% 
% % Create two sided Y and take istft
% Y = [zeros(1,L);Y;zeros(2,L);conj(flipud(Y))];
% yFrO = myOverlapAdd(Y); % yFrO = y Frost Online
% figure; plot(yFrO);
% 
% figure; semilogy(Wmse);
% figure; plot(Wmse);