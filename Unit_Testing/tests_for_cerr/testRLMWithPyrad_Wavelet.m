% this script tests run length texture features between CERR and pyradiomics on a wavelet filtered image.
%
% RKP, 03/22/2018


rlmParamFileName = fullfile(fileparts(fileparts(getCERRPath)),...
    'Unit_Testing','tests_for_cerr','test_rlm_radiomics_extraction_settings.json');
cerrFileName = fullfile(fileparts(fileparts(getCERRPath)),...
    'Unit_Testing','data_for_cerr_tests','CERR_plans','head_neck_ex1_20may03.mat.bz2');

planC = loadPlanC(cerrFileName,tempdir);
indexS = planC{end};

paramS = getRadiomicsParamTemplate(rlmParamFileName);
strNum = getMatchingIndex(paramS.structuresC{1},{planC{indexS.structures}.structureName});
scanNum = getStructureAssociatedScan(strNum,planC);


scanType = 'wavelet';
dirString = 'HHH';

%% Calculate features using CERR

rlmFeat3DdirS = calcGlobalRadiomicsFeatures...
            (scanNum, strNum, paramS, planC);
%firstOrderS = radiomics_first_order_stats(testM(logical(maskBoundingBox3M)), VoxelVol, offsetForEnergy, binwidth);
rlmCombS = rlmFeat3DdirS.Wavelets_Coif1__HHH.rlmFeatS.AvgS;

cerrRlmV = [rlmCombS.gln, rlmCombS.glnNorm, rlmCombS.glv, rlmCombS.hglre, rlmCombS.lglre, rlmCombS.lre, rlmCombS.lrhgle, ...
    rlmCombS.lrlgle, rlmCombS.rln, rlmCombS.rlnNorm, rlmCombS.rlv, rlmCombS.rp, ...
    rlmCombS.sre, rlmCombS.srhgle, rlmCombS.srlgle];


%% Calculate features using pyradiomics

testM = single(planC{indexS.scan}(scanNum).scanArray) - ...
    single(planC{indexS.scan}(scanNum).scanInfo(1).CTOffset);
mask3M = zeros(size(testM),'logical');
[rasterSegments, planC, isError] = getRasterSegments(strNum,planC);
[maskBoundBox3M, uniqueSlices] = rasterToMask(rasterSegments, scanNum, planC);
mask3M(:,:,uniqueSlices) = maskBoundBox3M;

teststruct = PyradWrapper(testM, mask3M, scanType, dirString);

pyradRlmNamC = {'GrayLevelNonUniformity', 'GrayLevelNonUniformityNormalized',...
    'GrayLevelVariance', 'HighGrayLevelRunEmphasis',  'LowGrayLevelRunEmphasis', ...
    'LongRunEmphasis', 'LongRunHighGrayLevelEmphasis', 'LongRunLowGrayLevelEmphasis',...
    'RunLengthNonUniformity', 'RunLengthNonUniformityNormalized', 'RunVariance', ...
    'RunPercentage', 'ShortRunEmphasis','ShortRunHighGrayLevelEmphasis', ...
    'ShortRunLowGrayLevelEmphasis'};

pyradRlmNamC = strcat(['wavelet','_', dirString, '_glrlm_'],pyradRlmNamC);

pyRadRlmV = [];
for i = 1:length(pyradRlmNamC)
    if isfield(teststruct,pyradRlmNamC{i})
        pyRadRlmV(i) = teststruct.(pyradRlmNamC{i});
    else
        pyRadRlmV(i) = NaN;
    end
end

rlmDiffV = (cerrRlmV - pyRadRlmV) ./ cerrRlmV * 100