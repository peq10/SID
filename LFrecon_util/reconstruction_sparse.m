function Xguess = reconstruction_sparse(in_file, psf_ballistic, options)

if nargin < 3
    options = struct;
end

if ~isfield(options,'maxIter')
    options.maxIter = 8;
end

if ~isfield(options,'whichSolver')
    options.whichSolver = 'fast_nnls';
end

if ~isfield(options, 'gpu_ids')
    options.gpu_ids = [4 5]; %the GPU ids to use for this job (valid on pcl-imp-2: 1,2,4,5)
end

%%
eqtol = 1e-10;
cluster = parcluster('local');
edgeSuppress = 0;


%% REPARE PARALLEL COMPUTING
pool = gcp('nocreate')
if ~pool.isvalid % checking to see if my pool is already open
    pool = parpool(cluster)
end

%% Load Data
if strcmp(class(psf_ballistic.H), 'double')
    psf_ballistic.H = single(psf_ballistic.H);
    psf_ballistic.Ht = single(psf_ballistic.Ht);
end
disp(['Size of PSF matrix is : ' num2str(size(psf_ballistic.H)) ]);


[n_px_x, n_px_y, n_frames] = size(in_file.LFmovie);

global volumeResolution;
volumeResolution = [n_px_x n_px_y size(psf_ballistic.H,5)];
disp(['Image size is ' num2str(volumeResolution(1)) 'X' num2str(volumeResolution(2))]);

%% prepare reconstruction of first frame
Nnum = size(psf_ballistic.H,3);
backwardFUN_ = @(projection) backwardProjectGPU_new(psf_ballistic.H, projection );
forwardFUN_ = @(Xguess) forwardProjectGPU( psf_ballistic.H, Xguess );
%prepare global gpu variables for reconstruction of the first frame.
%this does not affect the parallelization later on.
gpuDevice(options.gpu_ids(1));
global zeroImageEx;
global exsize;
xsize = [volumeResolution(1), volumeResolution(2)];
msize = [size(psf_ballistic.H,1), size(psf_ballistic.H,2)];
mmid = floor(msize/2);
exsize = xsize + mmid;
exsize = [ min( 2^ceil(log2(exsize(1))), 256*ceil(exsize(1)/256) ), min( 2^ceil(log2(exsize(2))), 256*ceil(exsize(2)/256) ) ];
zeroImageEx = gpuArray(zeros(exsize, 'single'));
disp(['FFT size is ' num2str(exsize(1)) 'X' num2str(exsize(2))]);

%% generate kernel

if ~isfield(options,'rad')
    options.rad=[2,2];
end

W=zeros(2*options.rad(1)+1,2*options.rad(1)+1,2*options.rad(2)+1);
for ii=1:2*options.rad(1)+1
    for jj=1:2*options.rad(1)+1
        for kk=1:2*options.rad(2)+1
            if  ((ii-(options.rad(1)+1))^2/options.rad(1)^2+(jj-(options.rad(1)+1))^2/options.rad(1)^2+(kk-(options.rad(2)+1))^2/options.rad(2)^2)<=1
                W(ii,jj,kk)=1;
            end
        end
    end
end
kernel=gpuArray(W);

forwardFUN = @(Xguess) forwardFUN_(convn(Xguess,kernel,'same'));
backwardFUN = @(projection) convn(backwardFUN_(projection),kernel,'same');

%% Reconstruction
LFIMG = single(in_file.LFmovie);
tic;
Xguess = backwardFUN(LFIMG);
ttime = toc;
disp(['  iter ' num2str(0) ' | ' num2str(options.maxIter) ', took ' num2str(ttime) ' secs']);



%%
if strcmp(options.whichSolver,'ISRA')
    Xguess = deconvRL(forwardFUN, backwardFUN, Xguess, maxIter, Xguess ,options);
elseif strcmp(options.whichSolver,'fast_nnls')
    Xguess=fast_deconv(forwardFUN, backwardFUN, Xguess, options.maxIter,options);
end

Xguess=gather(Xguess);
disp(['Volume reconstruction complete.']);
end