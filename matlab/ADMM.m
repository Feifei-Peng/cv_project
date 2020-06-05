function [im_out,psnr_out,ssim_out,history,iter_ims] = ADMM(y,A,InitEstFunc,params,orig_im)
    %   Run ADMM to solve minimize 
    %       E(x) = ||Ax-y||_2^2 + λ * 0.5*x'*(x-denoise(x))
    %   with the augmented lagrangian of form 
    %       L_{ρ}(x,v) = ||Ax-y||_2^2 + λ * 0.5*x'*(x-denoise(x)) + 
    %                        μ^T(x-v) + (ρ/2) ||x-z||_2^2
    %   
    % Inputs:
    %   y                        input image
    %   A                        multiplexing and spatial subsampling operator
    %   InitEstFunc              initial guess of `y` based on `x`
    %   params.
    %       lambda               relative scaling of data term and regularization term
    %       rho                  augmented lagrangian parameter
    %       outer_iters          number of ADMM iterations
    %       inner_denoiser_iters number of fixed iterations in v-minimization step
    %       denoiser_type        denoiser used in v-minimization step
    %       effective_sigma      input noise level to denoiser
    % 
    % Outputs:
    %   im_out                   imputed image
    %   psnr_out                 psnr of `im_out` to `orig_im`
    %   ssim_out                 ssim of `im_out` to `orig_im`
    %   statistics               psnrs at each iterations
 
    QUIET = 0;
    PRINT_MOD = floor(params.outer_iters/10);
    if ~QUIET
        fprintf('%7s\t%10s\t%12s\n', 'iter', 'PSNR/SSIM', 'objective');
    end

    lambda = params.lambda;
    rho = params.rho;
    outer_iters = params.outer_iters;
    inner_denoiser_iters = params.inner_denoiser_iters;
    denoiser_type = params.denoiser_type;
    effective_sigma = params.effective_sigma;
    v_update_method = params.v_update_method;
    
    x_est = InitEstFunc(y);
    z_est = x_est;
    u_est = zeros(size(x_est));
    save_iter = 1;

    [h,w,S] = size(x_est);
    ToIm = @(x) reshape(x,h,w,[]);
    
    % precomputation for x-update
    if isdiag(A*A') ~= 1
        warning("A*A' with optimal multiplexing matrix W is diagonal");
    end
    zeta = full(diag(inv(A*A')));

    % iter_ims = zeros(5*h,S*w,outer_iters);
    history.psnrs = []; history.ssims = []; history.costfuncs = [];
    
    for k = 1:outer_iters

        x_old = x_est;
        v_old = z_est;
        u_old = u_est;
    
        % primal x update
        x_est = z_est-u_est;
        x_est = x_est + A'*( (y(:) - A*x_est(:))./(rho+zeta) );
        x_est = ToIm( Clip(x_est,0,255) );
        
        % primal v update
        switch v_update_method
        case "fixed_point"
            for j = 1:1:inner_denoiser_iters
                denoised_z_est = Denoiser(z_est,effective_sigma,denoiser_type);
                z_est = (rho*(x_est+u_est) + lambda*denoised_z_est)/(lambda + rho);
            end
        case "denoiser"
            z_est = Denoiser(x_est+u_est,lambda/rho,denoiser_type);
        otherwise
            warning("v-update method not correct");
        end
    
        % scaled dual u update
        u_est = u_est + x_est - z_est;
    
        if ~QUIET && (mod(k,PRINT_MOD) == 0 || k == outer_iters)
            f_est = Denoiser(x_est,effective_sigma,denoiser_type);
            costfunc = norm(reshape(ToIm(A*x_est(:))-y,[],1)) + lambda*x_est(:)'*(x_est(:)-f_est(:));
            im_out = x_est(1:size(orig_im,1), 1:size(orig_im,2),:);
            [psnr,ssim] = ComputePSNRSSIM(orig_im, im_out);

            fprintf('%7i %.5f/%.5f %12.5f \n',k,psnr,ssim,costfunc);
            history.psnrs = [history.psnrs psnr];
            history.ssims = [history.ssims ssim];
            history.costfuncs = [history.costfuncs, costfunc];
            save_iter = save_iter + 1;

            imshow(2*FlattenChannels(orig_im,x_old,x_est,v_old,z_est,u_old,u_est)/255);
        end
    end
    
    im_out = x_est(1:size(orig_im,1), 1:size(orig_im,2),:);
    im_out = Clip(x_est,0,255);
    [psnr_out,ssim_out] = ComputePSNRSSIM(orig_im, im_out);
end