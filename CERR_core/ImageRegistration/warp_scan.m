function planC = warp_scan(deformS,movScanNum,movPlanC,planC,tmpDirPath)
% function planC = warp_scan(deformS,movScanNum,movPlanC,planC,tmpDirPath)
%
% APA, 07/19/2012

if ~exist('tmpDirPath','var')
    tmpDirPath = fullfile(getCERRPath,'ImageRegistration','tmpFiles');
end

% Convert moving scan to .mha
indexMovS = movPlanC{end};
movScanUID = movPlanC{indexMovS.scan}(movScanNum).scanUID;
movScanOffset = movPlanC{indexMovS.scan}(movScanNum).scanInfo(1).CTOffset;
movScanName = movPlanC{indexMovS.scan}(movScanNum).scanType;
movScanName = [movScanName,'_deformed'];
randPart = floor(rand*1000);
movScanUniqName = [movScanUID,num2str(randPart)];
movScanFileName = fullfile(tmpDirPath,['movScan_',movScanUniqName,'.mha']);
success = createMhaScansFromCERR(movScanNum, movScanFileName, movPlanC);


% Create b-spline coefficients file
if isstruct(deformS)
    baseScanUID = deformS.baseScanUID;
    movScanUID  = deformS.movScanUID;
    algorithm = deformS.algorithm;
else
    algorithm = 'PLASTIMATCH';
end
switch upper(algorithm)
    case 'ELASTIX'
        % Generate name for the output directory        
        warpedDir = fullfile(tmpDirPath,['warped_scan_',baseScanUID,'_',movScanUID]);   
        
        if ~exist(warpedDir,'dir')
            mkdir(warpedDir)
        end
        
        % Read Elastix build path from CERROptions.json
        optName = fullfile(getCERRPath,'CERROptions.json');
        optS = opts4Exe(optName);
        elxTransformCmd = 'transformix';
        if exist(optS.elastix_build_dir,'dir')
            %cd(optS.elastix_build_dir)
            if isunix
                elxTransformCmd = ['sh ', fullfile(optS.elastix_build_dir,elxTransformCmd)];
            else
                elxTransformCmd = fullfile(optS.elastix_build_dir,[elxTransformCmd,'.exe']);
            end
        end
        transformC = fieldnames(deformS.algorithmParamsS);
        for iTransform = 1:length(transformC)
            fileC = deformS.algorithmParamsS.(transformC{iTransform});
            transformFileName = fullfile(warpedDir,[transformC{iTransform},'.txt']);
            fileC = fileC(:);
            numRows = length(fileC);
            ind = [];
            indNoTf = [];
            for row = 1:numRows
                ind = strfind(fileC{row},'(InitialTransformParametersFileName');
                indNoTf = strfind(fileC{row},...
                    '(InitialTransformParametersFileName "NoInitialTransform")');
                if ~isempty(ind) || ~isempty(indNoTf)
                    break
                end
            end            
            if ~isempty(ind) && isempty(indNoTf)
                indV = strfind(fileC{row},'"');
                strTf = fileC{row};
                tfFileName = strTf(indV(1)+1:indV(2)-1);
                [~,fname,ext] = fileparts(tfFileName);
                fname = [fname(1:end-2),'_',fname(end)];
                fname = fullfile(warpedDir,[fname,ext]);                
                newStr = ['(InitialTransformParametersFileName "',fname,'")'];
                fileC{row} = newStr;
            end
            cell2file(fileC,transformFileName);
        end
        indV = cellfun(@(x) str2double(x(end)),transformC); % will work only up to 9 transforms
        lastTransform = max(indV);
        lastTransformName = fullfile(warpedDir,...
            ['TransformParameters_',num2str(lastTransform),'.txt']);
        %elxTransformCmd = [elxTransformCmd,' -def all -out ',...
        %    outputDirectory, ' -tp ',lastTransformName]; % DVF
        % fullfile(outputDirectory,'deformationField.mhd'); % Name of mhd
        % file containing DVF
        elxTransformCmd = [elxTransformCmd,' -in ',movScanFileName,...
            ' -out ',warpedDir, ' -tp ',lastTransformName];
        system(elxTransformCmd)    
        
        warpedNrrdFileName = fullfile(warpedDir,'result.nrrd');
        
        % Read the warped output .nrrd file within CERR
        [data3M, infoS] = nrrd_read(warpedNrrdFileName);
        data3M = permute(data3M,[2,1,3]); % required since mha2cerr.m does this: permute(data3M,[2,1,3])
        datamin = min(data3M(:));
        movScanOffset = 0;
        if datamin < 0
            movScanOffset = -datamin;
        end
        save_flag = 0;
        planC  = mha2cerr(infoS,data3M,movScanOffset,movScanName, planC, save_flag);
        
        % Cleanup
        try
            delete(movScanFileName)
            rmdir(warpedDir,'s')
        end       
        
        
    case 'ANTS'
    otherwise % plastimatch
        % Generate name for the output .mha file
        warpedMhaFileName = fullfile(tmpDirPath,...
            ['warped_scan_',baseScanUID,'_',movScanUID,'.mha']);        
        
        if ~isstruct(deformS)
            bspFileName = deformS;
            %indexS = planC{end};
            %movScanUID = movPlanC{indexMovS.scan}(movScanNum).scanUID;
            %baseScanUID = planC{indexS.scan}(movScanNum).scanUID;
        else
            bspFileName = fullfile(getCERRPath,...
                'ImageRegistration','tmpFiles',...
                ['bsp_coeffs_',baseScanUID,'_',movScanUID,'.txt']);
        end
        success = write_bspline_coeff_file(bspFileName,deformS.algorithmParamsS);
        
        % Switch to plastimatch directory if it exists
        prevDir = pwd;
        
        % Build plastimatch warp command
        plmCommand = 'plastimatch warp ';
        optName = fullfile(getCERRPath,'CERROptions.json');
        optS = opts4Exe(optName);
        if exist(optS.plastimatch_build_dir,'dir') && isunix
            cd(optS.plastimatch_build_dir)
            plmCommand = ['./',plmCommand];
        end
        
        % Issue plastimatch warp command
        fail = system([plmCommand, '--input ', movScanFileName,...
            ' --output-img ', warpedMhaFileName, ' --xf ', bspFileName]);
        if fail % try escaping slashes
            system([plmCommand, '--input ', escapeSlashes(movScanFileName),...
                ' --output-img ', escapeSlashes(warpedMhaFileName),...
                ' --xf ', escapeSlashes(bspFileName)])
        end
        
        % Switch back to the previous directory
        cd(prevDir)      
        
        % Read the warped output .mha file within CERR
        infoS  = mha_read_header(warpedMhaFileName);
        data3M = mha_read_volume(infoS);
        %[data3M,infoS] = readmha(warpedMhaFileName);
        save_flag = 0;
        planC  = mha2cerr(infoS,data3M,movScanOffset,movScanName, planC, save_flag);
        
        % Cleanup
        try
            if isstruct(deformS)
                delete(bspFileName)
            end
            delete(movScanFileName)
            delete(warpedMhaFileName)
        end
        
        
end

