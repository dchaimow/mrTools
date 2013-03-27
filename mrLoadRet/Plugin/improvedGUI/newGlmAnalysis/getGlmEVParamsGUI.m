% getGlmEVParamsGUI.m
%
%        $Id$
%      usage: params = getGlmEVParamsGUI(thisView,params,useDefault)
%         by: julien besle
%       date: 03/12/2010
%    purpose: return EV specific parameters for GLM analysis
%

function [scanParams, params] = getGlmEVParamsGUI(thisView,params,useDefault)

keepAsking = 1;
groupNum = viewGet(thisView,'groupNum',params.groupName);
nScans = viewGet(thisView,'nScans',groupNum);
if ~isfield(params,'scanNum') || isempty(params.scanNum)
  params.scanNum = 1:nScans;
end
if isfield(params,'scanParams') && length(params.scanParams)==nScans
   scanParams = params.scanParams;
else
   % make the output as long as the number of scans
   scanParams = cell(1,nScans);
end
if ~isfield(params, 'EVnames') || ~isequal(length(params.EVnames),params.numberEVs) 
  EVnames = {};
else
  EVnames = params.EVnames;
end

while keepAsking
  % check for stimfile, and if it is mgl type then ask the
  % user which variable they want to do the analysis on
  for iScan = params.scanNum
    
    %get the number of events after running the pre-processing function
    disp(sprintf('Getting number of conditions from scan %d', iScan)); 
    d = loadScan(thisView, iScan, groupNum, 0);
    d = getStimvol(d,scanParams{iScan});
    d = eventRelatedPreProcess(d,scanParams{iScan}.preprocess);
    nStims = length(d.stimvol);
    disp(sprintf('%d conditions found', nStims));
    
    if ~params.numberEVs
      params.numberEVs = nStims;
    end
    if ~isfield(scanParams{iScan}, 'stimToEVmatrix') || isempty(scanParams{iScan}.stimToEVmatrix) || ...
      ~isequal(size(scanParams{iScan}.stimToEVmatrix,1),nStims) || ~isequal(size(scanParams{iScan}.stimToEVmatrix,2),params.numberEVs)
        scanParams{iScan}.stimToEVmatrix = eye(nStims,params.numberEVs);
    end
    if isempty(EVnames) 
      EVnames = repmat({' '},1,params.numberEVs);
      if params.numberEVs <= nStims
        EVnames = d.stimNames(1:params.numberEVs);
      else
        EVnames(1:nStims) = d.stimNames;
      end
    end

    paramsInfo = cell(1,nStims+4);
    paramsInfo{1}= {'scan', scanParams{iScan}.scan, 'editable=0','description of the scan'};
    paramsInfo{2}= {'EVnames', EVnames, 'type=stringarray','Name of the Explanatory Variables to be estimated. EVs that are set to 0 in all rows will be removed from the model.'};
    for iEvent = 1:nStims
      paramsInfo{iEvent+2} = {fixBadChars(d.stimNames{iEvent}), scanParams{iScan}.stimToEVmatrix(iEvent,:),...
        'incdec=[-1 1]','incdecType=plusMinus','minmax=[0 inf]',...
        ['How much stimulus ' fixBadChars(d.stimNames{iEvent}) ' contributes to each EV.']};
    end
    paramsInfo{nStims+3}= {'showDesign', 0, 'type=pushbutton','buttonString=Show Design','Shows the experimental design (before convolution with an HRF model) and the design matrix.)',...
            'callback',{@plotExperimentalDesign,scanParams,params,iScan,thisView,d.stimNames},'passParams=1'};

    % give the option to use the same parameters for remaining scans (assumes the event names are identical in all files)
    if (iScan ~= params.scanNum(end)) && (length(params.scanNum)>1)
      paramsInfo{nStims+4} = {'sameForNextScans',iScan == params.scanNum(1),'type=checkbox','Use the same parameters for all scans'};
    else
      paramsInfo(nStims+4) = [];
    end

    %%%%%%%%%%%%%%%%%%%%%%%
    % now we have all the dialog information, ask the user to set parameters
    if useDefault
       tempParams = mrParamsDefault(paramsInfo);
    else
       tempParams = mrParamsDialog(paramsInfo,'Set Stimulus/EV matrix');
    end

    % user hit cancel
    if isempty(tempParams)
       scanParams = tempParams;
       return
    end
    
    % form stimToEV matrix from fields
    stimToEVmatrix = zeros(nStims,params.numberEVs);
    for iEvent = 1:nStims
      stimToEVmatrix(iEvent,:) = tempParams.(fixBadChars(d.stimNames{iEvent}));
%       tempParams = mrParamsRemoveField(tempParams,fixBadChars(d.stimNames{iEvent}));
    end
    EVnames = tempParams.EVnames;
%     tempParams = mrParamsRemoveField(tempParams,'EVnames');
    EVsToRemove = find(~any(stimToEVmatrix,1));
    for iEV = EVsToRemove
      disp(sprintf('(getGlmEVParamsGUI) Removing EV ''%s'' because it is empty',EVnames{iEV}));
    end
    stimToEVmatrix(:,EVsToRemove) = [];
    EVnames(EVsToRemove)=[];
    %Add only these 2 parameters to the scanParams
    newParams =  mrParamsDefault({{'stimToEVmatrix',stimToEVmatrix,'Matrix forming EVs from combinations of stimulus types'},...
                       {'stimNames',d.stimNames,'type=strinArray','Names of stimulus types'}});
    scanParams{iScan} = mrParamsCopyFields(newParams,scanParams{iScan});
    %update number of EVs
    params.numberEVs = size(stimToEVmatrix,2);

    % if sameForNextScans is set, copy the temporary parameters into all remaining scans and break out of loop
    if isfield(tempParams,'sameForNextScans') && tempParams.sameForNextScans
      for jScan = params.scanNum(find(params.scanNum>iScan,1,'first'):end)
        % set the other scans params to the same as this one
        scanParams{jScan} = mrParamsCopyFields(newParams,scanParams{jScan});
      end
      break
    end
  %          paramsInfo = {};
    if keepAsking && useDefault %there were incompatible parameters but this is the script mode (no GUI)
      scanParams = [];
      return;
    end
  end
  params.EVnames = EVnames;
  keepAsking = 0;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%% plotStimDesign %%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function plotExperimentalDesign(thisScanParams,scanParams,params,scanNum,thisView,stimNames)

%we need to convert the stimToEVmatrix
for iEvent = 1:length(stimNames)
  thisScanParams.stimToEVmatrix(iEvent,:) = thisScanParams.(fixBadChars(stimNames{iEvent}));
end
thisScanParams.stimNames = stimNames;
EVsToRemove = find(~any(thisScanParams.stimToEVmatrix,1));
for iEV = EVsToRemove
  disp(sprintf('(getGlmEVParamsGUI) Removing EV %s because it is empty',thisScanParams.EVnames{iEV}));
end
thisScanParams.stimToEVmatrix(:,EVsToRemove) = [];
thisScanParams.EVnames(EVsToRemove)=[];

if ~isfield(thisScanParams,'sameForNextScans') || thisScanParams.sameForNextScans
  %if it's the last scan or sameForNextScans is selected, we show all scans
  %copy params to remaining scans
  for jScan = params.scanNum(find(params.scanNum==scanNum,1,'first'):end)
    scanParams{jScan} = copyFields(thisScanParams,scanParams{jScan});
  end
  scanList = params.scanNum;
else
  %otherwise we only show the current scan
  scanParams = cell(1,scanNum);
  scanParams{scanNum} = thisScanParams;
  scanList = scanNum;
end

nScans = length(scanList);
expDesignFigure = initializeFigure('plotExperimentalDesign',nScans,'horizontal');
designMatrixFigure = initializeFigure('plotDesignMatrix',nScans,'vertical');

cScan=0;
axisLength = zeros(1,length(params.scanNum));
tSeriesAxes = zeros(1,length(params.scanNum));
designMatrixAxes = zeros(1,length(params.scanNum));
for iScan = scanList
  params.scanParams{iScan} = copyFields(scanParams{iScan},params.scanParams{iScan}); %we use copyFields here instead of mrParamsCopyFields because the latter only copies fields with a corresponding paramInfo entry
  EVnames = thisScanParams.EVnames;
  colors = randomColors(length(EVnames));
  %replace all unused stimuli by one EV (if any)
  if any(~any(params.scanParams{iScan}.stimToEVmatrix,2))
    params.scanParams{iScan}.stimToEVmatrix(:,end+1) = ~any(params.scanParams{iScan}.stimToEVmatrix,2);
    EVnames{end+1} = 'Not used';
    colors(end+1,:) = [.85 .85 .85]; %last color for unused stims
  end
  
  d = loadScan(thisView, iScan, viewGet(thisView,'groupNum',params.groupName), 0);
  d = getStimvol(d,params.scanParams{iScan});
  [params.hrfParams,d.hrf] = feval(params.hrfModel, params.hrfParams, d.tr/d.designSupersampling,params.scanParams{iScan}.acquisitionDelay,1);
  d = eventRelatedPreProcess(d,params.scanParams{iScan}.preprocess);
  d = makeDesignMatrix(d,params,1,iScan);
  cScan=cScan+1;
  
  if ~isempty(d.scm) && size(d.scm,2)==length(EVnames)*d.nHrfComponents
    %the length for the axis depends on the number of volumes times the frame period
    axisLength(cScan) = size(d.EVmatrix,1)/d.designSupersampling*d.tr;

    tSeriesAxes(cScan) = axes('parent',expDesignFigure,'outerposition',getSubplotPosition(1,cScan,[7 1],ones(nScans,1),0,.05));
    hold(tSeriesAxes(cScan),'on')
    [h,hTransition] = plotStims(d.EVmatrix, d.stimDurations, d.tr/d.designSupersampling, colors, tSeriesAxes(cScan),d.runTransitions);

    title(tSeriesAxes(cScan),viewGet(thisView,'description',iScan),'interpreter','none');
    %legend
    legendStrings = EVnames(h>0);
    h = h(h>0);
    if ~isempty(hTransition)
      h = [h hTransition];
      legendStrings = [legendStrings {'Run Transitions'}];
    end
    lhandle = legend(h,legendStrings,'position',getSubplotPosition(2,cScan,[7 1],ones(nScans,1),0,.05));
    set(lhandle,'Interpreter','none','box','off');
    
    %plot the design matrix
    designMatrixAxes(cScan) = axes('parent',designMatrixFigure,'outerposition',getSubplotPosition(cScan,1,ones(nScans,1),[7 1],0,.05));
    dimensions = size(d.scm);
    extended_matrix = zeros(dimensions+1);
    extended_matrix(1:size(d.scm,1),1:size(d.scm,2)) = d.scm;
    hMatrix = pcolor(designMatrixAxes(cScan),(1:dimensions(2)+1)-.5,(1:dimensions(1)+1)-.5,  double(extended_matrix)); %first vector must correspond to columns of the matrix
                %and second vector to the rows... (how retarded is that ?)
    set(hMatrix,'EdgeColor','none');
    Xticks = 1:size(d.scm,2);
    set(designMatrixAxes(cScan), 'Ydir', 'reverse');
    ylabel(designMatrixAxes(cScan),'Scans');
    %set rotated component labels
    set(designMatrixAxes(cScan), 'Xtick', Xticks );
    xTickStringsStrings = cell(1,length(EVnames)*d.nHrfComponents);
    for i = 1:length(EVnames)
      for j = 1:d.nHrfComponents
        xTickStringsStrings{(i-1)*d.nHrfComponents+j}=[EVnames{i} ' - Component ' num2str(j)];
      end
    end
    axisCoords = axis(designMatrixAxes(cScan)); % Current axis limits
    text(Xticks,axisCoords(4)*ones(1,length(Xticks)),xTickStringsStrings,...
      'parent',designMatrixAxes(cScan),'HorizontalAlignment','right',...
      'VerticalAlignment','top','Rotation',45,'interpreter','none');
    % Remove the default labels
    set(designMatrixAxes(cScan),'XTickLabel','')
    colormap(designMatrixAxes(cScan),gray);
    %add run transitions
    if ~isempty(d.runTransitions)
      hold(designMatrixAxes(cScan),'on');
      for iRun = 2:size(d.runTransitions,1)
        hTransitionDesign = plot(designMatrixAxes(cScan),axisCoords(1:2),repmat(d.runTransitions(iRun,1)/d.designSupersampling,1,2),'--r');
      end
    end
    if iScan==scanList(end)
      hColorbar = colorbar('peer',designMatrixAxes(cScan));
      if size(d.runTransitions,1)>1
        colorBarPosition = get(hColorbar,'position');
        legendPosition = colorBarPosition;
        legendPosition(2)= colorBarPosition(2)/2;
        legendPosition(3)= 1-colorBarPosition(1);
        legendPosition(4)= colorBarPosition(2)/2;
        legendHandle = legend(hTransitionDesign,{'Run transitions'},'Position',legendPosition);
        set(legendHandle,'Interpreter','none','box','off');
      end
    end
    
  else
    h = axes('parent',expDesignFigure,'outerposition',getSubplotPosition(1,cScan,[7 1],ones(nScans,1),0,.05));   
    set(h,'visible','off');
    text(.5,.5,{viewGet(thisView,'description',iScan), 'Number of EVs does not match', 'Change the stimToEV matrix for this scan'},...
      'parent',h,'units','normalized','HorizontalAlignment','center');
  end
end

%resize axes according to length of each sequence
maxAxisLength = max(axisLength);
for iScan = 1:cScan
  if axisLength(iScan)
    figurePosition = get(tSeriesAxes(iScan),'position');
    figurePosition(3) = figurePosition(3)*axisLength(iScan)/maxAxisLength;
    set(tSeriesAxes(iScan),'position',figurePosition);
  end
end

function expDesignFigure = initializeFigure(figureName,nScans,mode)

expDesignFigure = selectGraphWin(0,'Make new');
set(expDesignFigure,'name',figureName);
monitorPositions = getMonitorPositions;
figurePosition = get(expDesignFigure,'position');
[whichMonitor,figurePosition]=getMonitorNumber(figurePosition,monitorPositions);
screenSize = monitorPositions(whichMonitor,:); % find which monitor the figure is displayed in
switch(mode)
  case 'horizontal'
    figurePosition(3) = screenSize(3);
    figurePosition(4) = min(screenSize(3)/8*nScans,screenSize(4));
  case 'vertical'
    figurePosition(1) = screenSize(1);
    figurePosition(2) = min(screenSize(1)/8*nScans,screenSize(2));
end
set(expDesignFigure,'position',figurePosition);