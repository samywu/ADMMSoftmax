clear all; 

addpath(genpath('~/ADMMSoftmaxCode/'));

N = 50000; Ntrain = 0.8*N; Nval = 0.2*N; Ntest = 0.2*N;

layer = 'pool5';
[Dtrain,Ctrain,Dval,Cval,Dtest,Ctest] = setupCIFAR10AlexNet(N, Ntest, layer);
Dtrain = double(Dtrain); Dtest = double(Dtest); Dval = double(Dval);
nf = size(Dtrain,1); 
nc = size(Ctrain,1);

fprintf('maxDtrain = %1.2e, minDtrain = %1.2e\n', max(Dtrain(:)), min(Dtrain(:)));
fprintf('maxDval = %1.2e, minDval = %1.2e\n', max(Dval(:)), min(Dval(:)));

Dtrain    = normalizeData(Dtrain, size(Dtrain,1));
Dval      = normalizeData(Dval, size(Dval,1));
Dtest     = normalizeData(Dtest, size(Dtest,1));
fprintf('maxDtrain = %1.2e, minDtrain = %1.2e\n', max(Dtrain(:)), min(Dtrain(:)));
fprintf('maxDval = %1.2e, minDval = %1.2e\n', max(Dval(:)), min(Dval(:)));

%% regularization
alpha = 1e-1;
addBias=true;
nImg = [6 6]; channelsOut = 256; % pool 5
% smoothness reg. operator
fprintf('using smoothness! reg. operator...\n')
Ltemp = getLaplacian(nImg, 1./nImg);

L = genBlkDiag(Ltemp,channelsOut-1);

%  add bias to laplace operator 
if addBias==true
    L = sparse([L zeros(size(L,1),1); zeros(1,size(L,2)) 1]);
end

Lout = sparse(genBlkDiag(L, nc-1));

% account for mesh size: 
Lout = Lout/(nf);
L    = L/(nf);

fprintf('size of Lout = %d = %1.2e...\n', size(Lout,1))
fprintf(' max of Lout... ');
max(Lout(:))

if addBias==true
    w0      = (zeros(nc,nf+1));
    Dtrain  = [Dtrain; ones(1,Ntrain)];
    Dval    = [Dval; ones(1,Nval)];
    Dtest   = [Dtest; ones(1,Ntest)];
    Wref    = zeros(nc,nf+1);
else
    w0      = (zeros(nc,nf));
    Wref    = zeros(nc,nf);
end

size(Dtrain)

%% start optimization
pRegW   = tikhonovReg(Lout,alpha);
pLoss   = softmaxLossZ();
f       = classObjFctn(pLoss,pRegW,Dtrain,Ctrain);
fVal   = classObjFctn(pLoss,pRegW,Dval,Cval);

f.pLoss.addBias=0; fVal.pLoss.addBias=0;

%% initial admm values
rho0 = 8e-12; 
maxIter = 10000; atol = 1e-12; rtol = 1e-12;
out=1; varRho=0; scaleRho = 2; mu = 10;
rhoLowerBound = 1e-16;
rhoUpperBound = 1e3;
% 1)iter 2)Fw 3)Fval, 4)trainAcc 5)valAcc 6)Ziters 7)Fz 8)Zres 9)lagrangian
%10) resPri 11)epsPri 12)resDual 13)epsDual 14)rho 15)currentRuntime

%% LeastSquares solver
lsSolver = 'qr'; % 'cholesky', or 'qr'
% lsSolver = 'backslash';

%% Z-step parameters
maxIterZ = 100; % max number of Z newton iters
linSolMaxIterZ = 50; % max number of CG iters per newton step in Z step
lsMaxIterZ= 20; % max number of linesearch armijo iters per lin sol in Z step
atolZ = 1e-6; rtolZ=1e-6; % abs and rel tolerance for z solve
outZ = 0; % output for Z solve
linSolTolZ = 1e-6; % tolerance of linear solver (steihaug CG) for Z newton step
%% stopping criteria
% stoppingCrit{1} = 'regular';
% stoppingCrit{1} = 'training'; stoppingCrit{2} = 90; % stop when 90% training
stoppingCrit{1} = 'runtime'; stoppingCrit{2} = 300; % stop after 10 seconds
% stoppingCrit{1} = 'maxiters'; stoppingCrit{2} = 20; % stop after 50 iters

%% setup param structure

param.maxIter         = maxIter;
param.stoppingCrit    = stoppingCrit;
param.varRho          = varRho;
param.rhoLowerBound   = rhoLowerBound;
param.rhoUpperBound   = rhoUpperBound;
param.mu              = mu;
param.atol            = atol;
param.rtol            = rtol;
param.alpha           = alpha;
param.lsSolver        = lsSolver;
param.addBias         = addBias;
param.rho0            = rho0;
param.scaleRho        = scaleRho;
param.out             = out;


param.Wref            = Wref;
param.Dtrain          = Dtrain;
param.Dval            = Dval;
param.Ctrain          = Ctrain;
param.Cval            = Cval;
param.L               = L;

param.f               = f; % class obj func with training data
param.fVal            = fVal; % class obj func with val data

% z parameters
param.atolZ           = atolZ;
param.rtolZ           = rtolZ; 
param.maxIterZ        = maxIterZ;
param.linSolMaxIterZ  = linSolMaxIterZ;
param.linSolTolZ      = linSolTolZ;
param.lsMaxIterZ      = lsMaxIterZ;
param.outZ            = outZ;

%% train
[wFinal, wOptLoss, wOptAcc, hisOpt] = admmSoftmax(w0, param);

%% save best validation loss values
% WDLoss = reshape(wOptLoss, nc, [])*Dval;
WDLoss = wOptLoss*Dval;

[FcValLoss, paraValLoss] = fVal.pLoss.getMisfit(WDLoss, Cval);
errValLoss = paraValLoss(3);
accValLoss = 100*(Nval-errValLoss)/Nval;

% save best validation accuracy values
% WDAcc = reshape(wOptAcc, nc, [])*Dval;
WDAcc = wOptAcc*Dval;

[FcValAcc, paraValAcc] = fVal.pLoss.getMisfit(WDAcc, Cval);
errValAcc = paraValAcc(3);
accValAcc = 100*(Nval-errValAcc)/Nval;

fprintf('\n ------ VALIDATION RESULTS ------ \n')
fprintf('\n wOptLoss: fVal = %1.2e, accVal = %1.2f\n', FcValLoss, accValLoss);
fprintf('\n wOptAcc: fVal = %1.2e, accVal = %1.2f\n', FcValAcc, accValAcc);


%% check testing accuracy
pLossTest = softmaxLoss();
fTest     = classObjFctn(pLossTest,pRegW,Dtest(1:end-1,:),Ctest);

% weights that minimize validation misfit
[FcTestLoss, paraTestLoss] = fTest.eval(wOptLoss(:));
errTestLoss = paraTestLoss.hisLoss(3);
accTestLoss = 100*(Ntest-errTestLoss)/Ntest;

% weights that maximize validation accuracy
[FcTestAcc, paraTestAcc] = fTest.eval(wOptAcc(:));
errTestAcc = paraTestAcc.hisLoss(3);
accTestAcc = 100*(Ntest-errTestAcc)/Ntest;

fprintf('\n ------ TESTING RESULTS ------ \n')
fprintf('\n wOptLoss: fTest = %1.2e, accTest = %1.2f\n', FcTestLoss, accTestLoss);
fprintf('\n wOptAcc: fTest = %1.2e, accTest = %1.2f\n', FcTestAcc, accTestAcc);


saveResults=0;
if saveResults==1
    save('admmResultsCIFAR10.mat', 'hisOpt', 'wOptLoss', 'wOptAcc', 'wFinal', 'alpha', 'atol', 'rtol', 'atolZ', 'rtolZ', 'linSolMaxIterZ', 'lsMaxIterZ', 'maxIterZ', 'rho0', 'FcTestLoss', 'accTestLoss', 'FcTestAcc', 'accTestAcc')
end
