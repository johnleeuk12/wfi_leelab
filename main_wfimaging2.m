
%{
    Leelab Widefield Imaging data processing and basic analysis code.
Written by Jong Hoon Lee, with the help of Seung Mi Oh.

    The code is currently written to process data from XXXXXXX, where each
frame is saved as a TIFF file. core functions, such as the mouse atlas 
reference points from Allen Institutes, are required for this code to run.
The code was based on You Hyang Song's code for wide-field imaging analysis
for referencing and alignment, and on Anne Churchland's lab's code for 
extracting relevent signal through dimensionality reduction

Please update StimParameters.m to match your current experiment, and change
the number of stimuli and stimuli type, as well as trialNum in the config 
file.



    %%%%%%%%%%%%%%%%%%%%%% EDIT LOG %%%%%%%%%%%%%%%%%%%%%%%%

11/25/2020 JHL
    Code slightly modified to analyze single stimulus data. currently 
    different experiments have different stimulus id files (log files) 
    so the code in step1 must be adjusted. Future plans involve putting
    stim relevant information in StimParameters
    

01/12/2022 JHL
    Code completely rehauled to remove dF/F calculations by YHS and 
    implement SVD as done in Anne Churchland's lab. The code now produces
    a TIFF stack instead of TIF files and a movie
    


%}
close all
clear all


% run configuration file 
pathToYourConfigFile = 'D:\GitHub\LeeLab\wfi_leelab'; 
run(fullfile(pathToYourConfigFile, 'wfi_config.m'))


% add filepath for necessary functions
opts.data_dir = 'D:\GitHub\LeeLab';
addpath(genpath(fullfile(opts.data_dir, filesep, 'wfi_leelab'))); 

% read presentation log-file




%%

% Initializing functions and pathways
opts = wfi_init(opts);

% Reference check and defining boundaries. Run again to redefine boundaries
% before running the rest of the code
opts = reference_check(opts);

% get warp mask for alignment

load('ROI_to2.mat');

K = ones(512,512);
invtform = invert(opts.tform);
rotated_ROI_to2 = imwarp(gpuArray(ROI_to2),invtform,'OutputView',imref2d(size(K)));
rotated_ROI_to2 = imresize(rotated_ROI_to2,1);

rotated_ROI_to2 = gather(rotated_ROI_to2);



%% run dimensionality reduction
[bV,bS, bU, blockInd, wfAvg] = blockSVD_wf(opts,rotated_ROI_to2); %this loads raw data and does the first blockwise SVD

%% create whole-frame components
%merge dimensions if bV is in dims x trials x frames format
if iscell(bV)
    bV = cat(1,bV{:});
    if length(size(bV)) == 3
        bV = reshape(bV,size(bV,1), []);
    end
end

% combine all blue blocks and run a second SVD
[nU, s, nV] = fsvd(bV,opts.dimCnt); %combine all blocks in a second SVD
nV = s * nV'; %multiply S into V
Sv = diag(s); %keep eigenvalues

% figure
% test = Sv.*Sv;
% test = cumsum(test)/sum(test);
% plot(cumsum(Sv)/sum(Sv));


%% combine blocks back into combined components
[~, cellSize] = cellfun(@size,bU,'UniformOutput',false);
cellSize = cat(2,cellSize{:}); % get number of components in each block

% rebuild block-wise U from individual blocks
blockU = zeros(numel(wfAvg), sum(cellSize),'single');
edgeNorm = zeros(numel(wfAvg),1,'single');
Cnt = 0;
for iBlocks = 1 : length(bU)
    cIdx = Cnt + (1 : size(bU{iBlocks},2));
    blockU(blockInd{iBlocks}, cIdx) = blockU(blockInd{iBlocks}, cIdx) + bU{iBlocks};
    edgeNorm(blockInd{iBlocks}) = edgeNorm(blockInd{iBlocks}) + 1;
    Cnt = Cnt + size(bU{iBlocks},2);
end
edgeNorm(edgeNorm == 0) = 1; %remove zeros to avoid NaNs in blockU

%normalize blockU by dividing pixels where blocks overlap
blockU = bsxfun(@rdivide, blockU, edgeNorm);

% project block U on framewide spatial components
dSize = size(blockU);
blockU = reshape(blockU,[],dSize(end)); %make sure blockU is in pixels x componens
U = blockU * nU; %make new U with framewide components
disp('Second SVD complete'); toc;

nV = reshape(nV, size(nV,1), [], 1); % split channels
rotatROI = reshape(rotated_ROI_to2,1,[]);
% U2 = U.*rotatROI.';
U2 = U;
U = reshape(U,size(wfAvg,1),size(wfAvg,2),[]); %reshape to frame format

%% filter, smooth and find traces

Vout = SvdFluoCorrect(opts, U, nV, 10, 1);



%% dF/F0 analysis on temporal components
% baseline_arr = [];
% for tr = 1:fileCnt
%     baseline_arr = [baseline_arr,(tr-1)*opts.nFrames+1:(tr-1)*opts.nFrames+10];
% end
% 
% % nVbase= mean(nV(:,baseline_arr),2); % subtract baseline activity
% % nV2 = (nV-nVbase)./nVbase;           % divide by baseline activity 
% 
% % figure
% % for k = 1:20
% %     test = mean(reshape(nV(k,:),[],20),2);
% %     plot(test)
% %     hold on
% %     pause
% % end
% % Vbase= mean(Vout(:,baseline_arr),2); % subtract baseline activity
% Vout2 = Vout./abs(nVbase);           % divide by baseline activity 
% 
% 


%%
fileCnt = opts.StimTypeOrder{1}(end,1);

opts.dims2 = 100;

data_re = U2(:,1:opts.dims2)*Vout(1:opts.dims2,:);
data_dim1 = U2(:,1)*nV(1,:);

% data_re = bsxfun(@rdivide,data_re,data_dim1);
% 
% data_re(isnan(data_re)) =0;
% % 
data_re = reshape(data_re,size(wfAvg,1),size(wfAvg,2),[]);
% data_re = reshape(data_dim1,size(wfAvg,1),size(wfAvg,2),[]);
% imagesc(data_re(:,:,1))

mean_data = mean(reshape(data_re,size(wfAvg,1),size(wfAvg,2),[],fileCnt),4);

min_max = [min(min(min(mean_data))),max(max(max(mean_data)))];

% mean_data = mean_data/max(abs(min_max));

figure
for tr = 1:70
    imagesc(mean_data(:,:,tr))
    caxis(min_max);
    pause(0.1)
end


%% debugging 

figure

test2 = reshape(Vout,200,[],fileCnt);
test2 = mean(test2,3);

for tr = 1:10
    plot(test2(tr,:))
    hold on
end


%% produce and save data
tic
wf_gen_image(mean_data, ROI_to2,1, 1, opts,0);
toc
