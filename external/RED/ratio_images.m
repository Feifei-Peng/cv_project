% Compare performance of RED when input_im is in {ratio,intensity} space
%       the idea is that in ratio space, texture removed, so might be easier to do reconstruction
clc; clear; close all;
addpath(genpath('./tnrd_denoising/'));
addpath(genpath('./minimizers/'));
addpath(genpath('./parameters/'));
addpath(genpath('./helper_functions/'));
addpath(genpath('./test_images/'));
addpath(genpath("./mian/helperFunctions/Camera"));
addpath(genpath("./mian/helperFunctions/ASNCC"));
addpath(genpath("./mian/helperFunctions/Algorithms"));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% set to 1 if debug, 0 otherwise
short = 0;
% crop the image to remove the borders
[cx,cy] = deal(1:160,10:247);
% #patterns/frames
[S,F] = deal(4,3);
% dimension of input image
[h,w] = deal(176,288);
[h,w] = deal(numel(cx),numel(cy));
% scale the intensity of image for better visualization 
scaling = 2;
% scene
scene = "flower";
% dataset
dataset_exp60 = SceneNames("exp60");
% directory containing the raw noisy images
rawimagedir =  "data/exp60";
% directory containing groundtruth images
stackeddir = "data/exp60/organized";
% save images to 
savedir = "results/ratio"; mkdir(savedir);
% black level 
blacklevelpath = "data/blacklevel_all1/blacklevel.mat";
if ~isfile(blacklevelpath)
    blackimsdir = "data/blacklevel_all1";
    ComputeBlackLevel(blackimsdir,h,w,blacklevelpath);
end
blacklvl = load(blacklevelpath);
blacklvl = blacklvl.blacklvl;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% RED-specific parameter
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% RED less #iterations
light_mode = true;
% sigmas 
input_sigma = 1;
% mask 
M = BayerMask(h,w);
% two-bucket multiplexing matrix
W = BucketMultiplexingMatrix(S)*2;
% linear map from S patterened image -> two bucket image
[H,B,C] = SubsampleMultiplexOperator(S,M);
% args to RunADMM
ForwardFunc = @(in_im) reshape(H*in_im(:),h,w,2);
BackwardFunc = @(in_im) reshape(H'*in_im(:),h,w,S);
InitEstFunc = InitialEstimateFunc("maxfilter",h,w,F,S, ...
        'BucketMultiplexingMatrix',W,'SubsamplingMask',M);
params_admm = GetSuperResADMMParams(light_mode);

params_admm_ratio = GetSuperResADMMParams(light_mode);
params_admm_ratio.beta = 0.01;
params_admm_ratio.lambda = 0.25;

if short == 1
    params_admm.outer_iters = 1;
    params_admm_ratio.outer_iters = 1;
else
    params_admm.outer_iters = 70;
    params_admm_ratio.outer_iters = 70;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compare RED on both ratio/intensity space
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% dataset_exp60 = ["shoe"];
m = {}; iter = 1;

for scene = dataset_exp60

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% read in image
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % intensity space
    orig_im_noisy = zeros(h,w,S);
    orig_im = zeros(h,w,S);
    input_im = zeros(h,w,2);

    % ratio space (scale by 255)
    ratio_orig_im = zeros(h,w,S);
    ratio_input_im = zeros(h,w,2);

    files = dir(sprintf("%s/%s/*.png",rawimagedir,scene));
    [fnames,ffolders] = deal({files.name},{files.folder});
    folder = ffolders{1};
    for i = 1:S
        fname = fnames{i};
        splits = split(fname,' ');
        [bktno,id] = deal(splits{1},splits{2}); assert(bktno == "bucket1");
        impath = sprintf("%s/%s",folder,fname);
        im = double(BlackLevelRead(impath,blacklvl,1));
        orig_im_noisy(:,:,i) = im(cx,cy);
    end

    input_im = ForwardFunc(orig_im_noisy);
    ratio_input_im = IntensityToRatio(input_im)*255;

    for s = 1:S
        im = double(imread(sprintf("%s/%s_%d.png",stackeddir,scene,s-1)));
        orig_im(:,:,s) = im(cx,cy);
    end

    ratio_orig_im = IntensityToRatio(orig_im)*255*(S/2); % *(S/2) to scale the intensity ...

    imshow([
        orig_im(:,:,1) orig_im(:,:,2) orig_im(:,:,3) orig_im(:,:,4)
        orig_im_noisy(:,:,1) orig_im_noisy(:,:,2) orig_im_noisy(:,:,3) orig_im_noisy(:,:,4)
        input_im(:,:,1) input_im(:,:,2) ratio_input_im(:,:,1) ratio_input_im(:,:,2)
        ratio_orig_im(:,:,1) ratio_orig_im(:,:,2) ratio_orig_im(:,:,3) ratio_orig_im(:,:,4)
    ]/255);

    assert(all(sum(ratio_input_im,3) -   255*ones(h,w) <= 1e-10,'all'));
    assert(all(sum(ratio_orig_im,3)  - 2*255*ones(h,w) <= 1e-10,'all'));

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% run RED on ratio/intensity images
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    params_admm.denoiser_type       = "tnrd";
    params_admm_ratio.denoiser_type = "tnrd";

    % 1: admm+tnrd in intensity space
    [admm_intensity_im,psnr_intensity,~] = RunADMM_demosaic(input_im,ForwardFunc,BackwardFunc,InitEstFunc,input_sigma,params_admm,orig_im);

    % 2. admm+tnrd in ratio space
    [admm_ratio_im,psnr_ratio,~] = RunADMM_demosaic(ratio_input_im,ForwardFunc,BackwardFunc,InitEstFunc,input_sigma,params_admm_ratio,ratio_orig_im);
    psnr_ratio = ComputePSNR(ratio_orig_im*(2/S),admm_ratio_im*((2/S))); % scale by 2/S to use PSNR formula where max_I=255
    
    % 3: admm+tnrd ratio images multiplied by total `input_im` intensity
    ratio_mult_inputsum_im = admm_ratio_im/255;
    ratio_mult_inputsum_im = RatioToIntensity(ratio_mult_inputsum_im,sum(input_im,3));
    psnr_ratio_mult_inputsum = ComputePSNR(orig_im,ratio_mult_inputsum_im);

    % 4: admm+tnrd ratio images multiplied by denoiseed (by tnrd) total `input_im` intensity
    denoised_input_im = Denoiser(sum(input_im,3),params_admm.effective_sigma,"tnrd");
    ratio_mult_inputsum_denoised_im = admm_ratio_im/255;
    ratio_mult_inputsum_denoised_im = RatioToIntensity(ratio_mult_inputsum_denoised_im,denoised_input_im);
    psnr_ratio_mult_inputsum_denoised = ComputePSNR(orig_im,ratio_mult_inputsum_denoised_im);


    fprintf("psnr_intensity                     %.4f\n",psnr_intensity);
    fprintf("psnr_ratio                         %.4f\n",psnr_ratio);
    fprintf("psnr_ratio_mult_inputsum           %.4f\n",psnr_ratio_mult_inputsum);
    fprintf("psnr_ratio_mult_inputsum_denoised  %.4f\n",psnr_ratio_mult_inputsum_denoised);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% save images
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    ims = [
        scaling*orig_im(:,:,1)                  scaling*orig_im(:,:,2)                  scaling*orig_im(:,:,3)                  scaling*orig_im(:,:,4)
        ratio_orig_im(:,:,1)                    ratio_orig_im(:,:,2)                    ratio_orig_im(:,:,3)                    ratio_orig_im(:,:,4)
        scaling*admm_intensity_im(:,:,1)        scaling*admm_intensity_im(:,:,2)        scaling*admm_intensity_im(:,:,3)        scaling*admm_intensity_im(:,:,4)
        admm_ratio_im(:,:,1)                    admm_ratio_im(:,:,2)                    admm_ratio_im(:,:,3)                    admm_ratio_im(:,:,4)
        scaling*ratio_mult_inputsum_im(:,:,1)   scaling*ratio_mult_inputsum_im(:,:,2)   scaling*ratio_mult_inputsum_im(:,:,3)   scaling*ratio_mult_inputsum_im(:,:,4)
        scaling*ratio_mult_inputsum_denoised_im(:,:,1)      scaling*ratio_mult_inputsum_denoised_im(:,:,2)      scaling*ratio_mult_inputsum_denoised_im(:,:,3)      scaling*ratio_mult_inputsum_denoised_im(:,:,4)
    ];
    
    imshow(ims/255);
    imwrite(uint8(ims),sprintf("%s/%s.png",savedir,scene));

    data.psnr_intensity = psnr_intensity;
    data.psnr_ratio = psnr_ratio;
    data.psnr_ratio_mult_inputsum   = psnr_ratio_mult_inputsum;
    data.psnr_ratio_mult_inputsum_denoised  = psnr_ratio_mult_inputsum_denoised;

    m{iter} = data;
    iter = iter + 1;
end


save(sprintf('%s/ratio_images.mat',savedir),'m');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Plots
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

m = load(sprintf('%s/ratio_images.mat',savedir));
m = m.m;
nx = numel(dataset_exp60);

psnrs = zeros(4,nx);
for i = 1:nx
    data = m{i};
    psnrs(1,i) = data.psnr_intensity;
    psnrs(2,i) = data.psnr_ratio;
    psnrs(3,i) = data.psnr_ratio_mult_inputsum;
    psnrs(4,i) = data.psnr_ratio_mult_inputsum_denoised;
end

plot(1:nx,psnrs(1,:),'DisplayName',"intensity"); hold on;
plot(1:nx,psnrs(2,:),'DisplayName','ratio'); hold on;
plot(1:nx,psnrs(3,:),'DisplayName','ratio multiplied with inputsum'); hold on;
plot(1:nx,psnrs(4,:),'DisplayName','ratio multiplied with denoised inputsum'); hold on;
set(gca,'xtick',1:nx,'xticklabel',dataset_exp60);
legend();
xlabel("Scenes")
ylabel("PSNR")
title("Performance comparison between intensity images and ratio images");
saveas(gcf,sprintf("%s/intensity_ratio_comparison.png",savedir));
hold off;



%%


% flower (medfilt)
% psnr (intensity-intensity)             44.006
% psnr (ratio->intensity - intensity)    44.446
% psnr (ratio - ratio)                   35.727


% tune lambda beta for ratio image
% defaults: lambda=0.008 beta=1e-3
% lambda=0.08000 beta=0.00100
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    40.739
% psnr (ratio - ratio)                   34.443


% lambda=0.30000 beta=0.00010
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    35.588
% psnr (ratio - ratio)                   28.404
% lambda=0.30000 beta=0.00100
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    43.233
% psnr (ratio - ratio)                   35.461
% lambda=0.30000 beta=0.00500
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    43.180
% psnr (ratio - ratio)                   36.362
% lambda=0.30000 beta=0.01000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    44.476
% psnr (ratio - ratio)                   36.438
% lambda=0.30000 beta=0.05000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    43.524
% psnr (ratio - ratio)                   36.269
% lambda=0.30000 beta=0.01000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    42.802
% psnr (ratio - ratio)                   35.935
% lambda=0.30000 beta=0.50000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    39.995
% psnr (ratio - ratio)                   33.434
% lambda=0.30000 beta=1.00000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    38.581
% psnr (ratio - ratio)                   31.864


% outer_iters=70 denoiser=tnrd
% lambda=0.10000 beta=0.01000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    44.683
% psnr (ratio - ratio)                   36.972
% lambda=0.25000 beta=0.01000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    45.656
% psnr (ratio - ratio)                   37.706
% lambda=0.50000 beta=0.01000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    44.277
% psnr (ratio - ratio)                   36.931
% lambda=0.75000 beta=0.01000
% psnr (intensity-intensity)             44.481
% psnr (ratio->intensity - intensity)    45.908
% psnr (ratio - ratio)                   36.369