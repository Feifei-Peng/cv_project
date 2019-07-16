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
% [cx,cy] = deal(51:80,51:80);
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
% params_admm_ratio.beta = 0.01;
% params_admm_ratio.lambda = 0.25;

if short == 1
    params_admm.outer_iters = 1;
    params_admm_ratio.outer_iters = 1;
else
    params_admm.outer_iters = 100;
    params_admm_ratio.outer_iters = 100;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% mimik how red converts rgb -> YCrBr 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

scene = "shoe";
params_admm.denoiser_type = "tnrd";
params_admm_ratio.denoiser_type = "tnrd";

orig_im_noisy = zeros(h,w,S);
orig_im = zeros(h,w,S);
input_im = zeros(h,w,2);
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


% S ratio images in the end
%       1. bayer demosaic+demultiplex, then compute ratio 
%       2. red demosaic+demultiplex, then compute ratio
%       3. compute ratio, then bayer demosaic+demultiplex
%       4. compute ratio, then red demosaic+demultiplex

ratio_ims = {};

DemosaicDemultiplex = InitialEstimateFunc("bayerdemosaic",h,w,F,S, 'BucketMultiplexingMatrix',W,'SubsamplingMask',M);
ratio_im1 = DemosaicDemultiplex(input_im);
ratio_im1 = IntensityToRatio(ratio_im1);
ratio_ims{1} = ratio_im1;

[ratio_im2,~,~] = RunADMM_demosaic(input_im,ForwardFunc,BackwardFunc,InitEstFunc,input_sigma,params_admm,orig_im);
ratio_ims{2} = Clip(IntensityToRatio(ratio_im2),0,1);

ratio_im3 = DemosaicDemultiplex(ratio_input_im);
ratio_ims{3} = Clip(ratio_im3/255,0,1);

[ratio_im4,~,~] = RunADMM_demosaic(ratio_input_im,ForwardFunc,BackwardFunc,InitEstFunc,input_sigma,params_admm_ratio,ratio_orig_im);
ratio_ims{4} = Clip(ratio_im4/255,0,1);

% adjust brightness ... 
for i = 1:3
    ratio_ims{i} = ratio_ims{i}*2;
end

% imshow([
%     ratio_ims{1}(:,:,1) ratio_ims{1}(:,:,2) ratio_ims{1}(:,:,3) ratio_ims{1}(:,:,4)
%     ratio_ims{2}(:,:,1) ratio_ims{2}(:,:,2) ratio_ims{2}(:,:,3) ratio_ims{2}(:,:,4)
%     ratio_ims{3}(:,:,1) ratio_ims{3}(:,:,2) ratio_ims{3}(:,:,3) ratio_ims{3}(:,:,4)
%     ratio_ims{4}(:,:,1) ratio_ims{4}(:,:,2) ratio_ims{4}(:,:,3) ratio_ims{4}(:,:,4)
% ]);

% demoninator for S ratio images 
%       1. simply the sum of input images
%       2. sum two bucket image, do bayer demosaic, then sum
%       3. red (bayerdemosaic+demultiplex), then sum the resulting S images

sum_ims = {};

sum_im1 = sum(input_im,3);
sum_ims{1} = sum_im1;

sum_im2 = sum(input_im,3);
sum_im2 = rgb2bgr(double(demosaic(uint8(sum_im2),'bggr')));
sum_ims{2} = sum(sum_im2,3)*(1/3);

[sum_im3,~,~] = RunADMM_demosaic(input_im,ForwardFunc,BackwardFunc,InitEstFunc,input_sigma,params_admm,orig_im);
sum_ims{3} = sum(sum_im3,3)/2;

% imshow([sum_ims{1} sum_ims{2} sum_ims{3}]/255);

% compare all combinations of `ratio_im` and `sum_im` 

psnrs = zeros(numel(ratio_ims),numel(sum_ims));
ims = zeros(numel(ratio_ims),numel(sum_ims),h,w,S);

for i = 1:numel(ratio_ims)
    for j = 1:numel(sum_ims)
        ratio_im = ratio_ims{i};
        sum_im = sum_ims{j};
        ratio_mult_sum = RatioToIntensity(ratio_im,sum_im);
        ims(i,j,:,:,:) = ratio_mult_sum;
        psnrs(i,j) = ComputePSNR(orig_im,ratio_mult_sum);
    end
end

psnr_baseline = ComputePSNR(orig_im,sum_im3);
fprintf("psnr_baseline (RED in intensity space): %.3f\n",psnr_baseline);
% 45.1312

out = [
    orig_im(:,:,1) orig_im(:,:,2) orig_im(:,:,3) orig_im(:,:,4)
    sum_im3(:,:,1) sum_im3(:,:,2) sum_im3(:,:,3) sum_im3(:,:,4)
];
imshow(3*out/255)


for s = 1:S
    out = zeros(numel(ratio_ims)*h,numel(sum_ims)*w);
    for i = 1:numel(ratio_ims)
        for j = 1:numel(sum_ims)
            out( ((i-1)*h+1):(i*h) , ((j-1)*w+1):(j*w) ) = squeeze(ims(i,j,:,:,s));
        end
    end
    imshow(out/255)
    imwrite(uint8(3*out),sprintf("%s/ratiocombinations_%s_S=%d.png",savedir,scene,s));
end


col_rownames = [
    "bayer -> compute ratio from S images"
    "red   -> compute ratio from S images"
    "compute ratio from 2 images -> bayer"
    "compute ratio from 2 image  -> red  "
];
col_input_image_sum = psnrs(:,1);
col_sum_bayerdemosaic_sum = psnrs(:,2);
col_red_sumSimages = psnrs(:,3);
t = table(col_rownames,col_input_image_sum,col_sum_bayerdemosaic_sum,col_red_sumSimages);
t


writetable(t,sprintf("%s/psnrs_ratio_combinations.txt",savedir));
% readtable(sprintf("%s/psnrs_masktypes_initialguesses.txt",savedir));



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compare RED on both ratio/intensity space for exp60
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



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compare RED on both ratio/intensity space for 7pattern
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

savedir = "results/ratio/7patterns"; mkdir(savedir);
rawimagedir =  "data/7patterns";
stackeddir = "data/7patterns/organized";
[S,F] = deal(7,6);
M = SubsamplingMask("toeplitz",h,w,F);
W = BucketMultiplexingMatrix(S)*4;
[H,B,C] = SubsampleMultiplexOperator(S,M);
ForwardFunc = @(in_im) reshape(H*in_im(:),h,w,2);
BackwardFunc = @(in_im) reshape(H'*in_im(:),h,w,S);
InitEstFunc = InitialEstimateFunc("maxfilter",h,w,F,S, ...
        'BucketMultiplexingMatrix',W,'SubsamplingMask',M);
dataset_7pattern = SceneNames("7patterns");

params_admm.outer_iters = 200;
params_admm_ratio.outer_iters = 200;
params_admm.denoiser_type       = "medfilter";
params_admm_ratio.denoiser_type = "medfilter";
%% 

m = {}; iter = 1;

for scene = dataset_7pattern

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
        ratio_orig_im(:,:,1) ratio_orig_im(:,:,2) ratio_orig_im(:,:,3) ratio_orig_im(:,:,4)
        orig_im_noisy(:,:,1) orig_im_noisy(:,:,2) orig_im_noisy(:,:,3) orig_im_noisy(:,:,4)
        input_im(:,:,1) input_im(:,:,2) ratio_input_im(:,:,1) ratio_input_im(:,:,2)
    ]/255);
    

    assert(all(sum(ratio_input_im,3) -     255*ones(h,w) <= 1e-10,'all'));
    assert(all(sum(ratio_orig_im,3)- (S/2)*255*ones(h,w) <= 0.5,'all'));
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% run RED on ratio/intensity images
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % 1: admm+tnrd in intensity space
    InitEstFunc = @(y) ratio_orig_im;
    params_admm_ratio.lambda = 0;
    [admm_intensity_im,psnr_intensity,~] = RunADMM_demosaic(input_im,ForwardFunc,BackwardFunc,InitEstFunc,input_sigma,params_admm,orig_im);

    % % 2. admm+tnrd in ratio space
    [admm_ratio_im,psnr_ratio,~] = RunADMM_demosaic(ratio_input_im,ForwardFunc,BackwardFunc,InitEstFunc,input_sigma,params_admm_ratio,ratio_orig_im);
    % psnr_ratio = ComputePSNR(ratio_orig_im*(2/S),admm_ratio_im*((2/S))); % scale by 2/S to use PSNR formula where max_I=255
    
    % % 3: admm+tnrd ratio images multiplied by total `input_im` intensity
    % ratio_mult_inputsum_im = admm_ratio_im/255;
    % ratio_mult_inputsum_im = RatioToIntensity(ratio_mult_inputsum_im,sum(input_im,3));
    % psnr_ratio_mult_inputsum = ComputePSNR(orig_im,ratio_mult_inputsum_im);

    % % 4: admm+tnrd ratio images multiplied by denoiseed (by tnrd) total `input_im` intensity
    % denoised_input_im = Denoiser(sum(input_im,3),params_admm.effective_sigma,"tnrd");
    % ratio_mult_inputsum_denoised_im = admm_ratio_im/255;
    % ratio_mult_inputsum_denoised_im = RatioToIntensity(ratio_mult_inputsum_denoised_im,denoised_input_im);
    % psnr_ratio_mult_inputsum_denoised = ComputePSNR(orig_im,ratio_mult_inputsum_denoised_im);


    fprintf("psnr_intensity                     %.4f\n",psnr_intensity);
    % fprintf("psnr_ratio                         %.4f\n",psnr_ratio);
    % fprintf("psnr_ratio_mult_inputsum           %.4f\n",psnr_ratio_mult_inputsum);
    % fprintf("psnr_ratio_mult_inputsum_denoised  %.4f\n",psnr_ratio_mult_inputsum_denoised);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% save images
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    ims = [
        scaling*orig_im(:,:,1)                  scaling*orig_im(:,:,2)                  scaling*orig_im(:,:,3)                  scaling*orig_im(:,:,4)
        ratio_orig_im(:,:,1)                    ratio_orig_im(:,:,2)                    ratio_orig_im(:,:,3)                    ratio_orig_im(:,:,4)
        scaling*admm_intensity_im(:,:,1)        scaling*admm_intensity_im(:,:,2)        scaling*admm_intensity_im(:,:,3)        scaling*admm_intensity_im(:,:,4)
        % admm_ratio_im(:,:,1)                    admm_ratio_im(:,:,2)                    admm_ratio_im(:,:,3)                    admm_ratio_im(:,:,4)
        % scaling*ratio_mult_inputsum_im(:,:,1)   scaling*ratio_mult_inputsum_im(:,:,2)   scaling*ratio_mult_inputsum_im(:,:,3)   scaling*ratio_mult_inputsum_im(:,:,4)
        % scaling*ratio_mult_inputsum_denoised_im(:,:,1)      scaling*ratio_mult_inputsum_denoised_im(:,:,2)      scaling*ratio_mult_inputsum_denoised_im(:,:,3)      scaling*ratio_mult_inputsum_denoised_im(:,:,4)
    ];
    
    imshow(ims/255);
    imwrite(uint8(ims),sprintf("%s/%s.png",savedir,scene));

    data.psnr_intensity = psnr_intensity;
    % data.psnr_ratio = psnr_ratio;
    % data.psnr_ratio_mult_inputsum   = psnr_ratio_mult_inputsum;
    % data.psnr_ratio_mult_inputsum_denoised  = psnr_ratio_mult_inputsum_denoised;

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
