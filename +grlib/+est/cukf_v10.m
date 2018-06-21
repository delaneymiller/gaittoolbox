%% cukf_v10 (added velocity-level knee constraint

%v11 will include accel bias in state/zero-velocity-update

% ***SPECIAL NOTE FOR v9: x containts [pos, vel, accel, quat, ang. vel.]' of each sensor
%resulting in a state vec of 48 elements (3 sensors, 16 states per sensor)
%order of sensors in state is MP, LA, RA
% z now containts [accel, quat, ang. vel]' x3 in order MP, LA, RA
% therefore, z has length = 3x10 = 30

function [ x_rec, xa_rec, qFEM, qlkVec, qrkVec, w_KN, PAR ] = cukf_v10(x,P,Q,R,N_MP,nMeas,acc,fs,...
    q_MP, q_LA, q_RA, w_MP_gfr__s, w_LA_gfr__s, w_RA_gfr__s, d_pelvis, d_lfemur, d_rfemur,...
    d_ltibia, d_rtibia,isConstr)
%% Unscented Kalman filter for state estimation of human lower limbs (a
% nonlinear dynamical system)
% [x_rec, xa_rec, qFEM] = ukf(x,P,Q,R,N_MP,nMeas,acc,fs,...
%    q_MP, q_LA, q_RA, d_pelvis, d_lfemur, d_rfemur,...
%   d_ltibia, d_rtibia,isConstr) assumes additive noise
%           x_k+1 = f(x_k) + w_k
%           z_k   = h(x_k) + v_k
% where w ~ N(0,Q) meaning w is gaussian noise with covariance Q
%       v ~ N(0,R) meaning v is gaussian noise with covariance R
% Inputs:   x: state at time K
%           P: "a priori" estimated state covariance
%           Q: initial estimated process noise covariance
%           R: initial estimated measurement noise covariance           z: current measurement
%           N_MP: number of timesteps to step forward using filter
%           nMeas: number of dimensions in measurment vec (mes. space)
%           acc: acceleration measuremnt matrix
%           fs: sampleing rate from sensors (1/fs = tiemstep length)
%           q__:q_MP,q_LA,q_RA quaternions of midpel, left ankle, right
%               ankle in gfr
%           w_: w_segment_rel2frame__describedInFrame: angular velocity of each sensor relative to gfr, described in sensor frame
%           d__:d_rtib, d_lfib, d_Lfem, d_rfem, d_pel is length of interest
%           (principle axis) in each segment
% Output:   x_rec: "a posteriori" state estimate
%           xa_rec: "a posteriori" augmented state components
%           qFEM: quaternion representing orientation of femur in gfr
	qlkVec = [];
	qrkVec = [];

	L = length(x);                                 %numer of states
	m = nMeas;
	alpha = 1e-4;     %should be small (0<alpha<1)                            %default, tunable
	ki = 0;            %start with 0 change if needed                           %default, tunable
	beta = 2;     % assuming gaussian then use 2                                %default, tunable
	%hjc = 3;%3 or 4 - see hingeJoint_cosntr func. for details
	lambda = alpha^2*(L+ki)-L;                    %constant
	c = L+lambda;                                 %constant
	Wm = [lambda/c 0.5/c*ones(1,2*L)];           %weight means
	Wc = Wm;
	Wc(1) = Wc(1)+(1-alpha^2+beta);               %weight covariance
	mu = sqrt(c);
	S = chol(P)';
	%S = eye(L);
	%disp(size(S))
	x_rec = nan(L,N_MP);
	xa_rec = nan(12,N_MP); % 12 = femur proximal and distal points, both legs(2x2x3)
	qFEM = nan(8,N_MP); %8 = 4 per quaterinoin and 2 legs
	w_KN = nan(2,N_MP);
	%vanderwerve 2001 paper wm, wc, and constant definitions

	for k=1:N_MP
		if mod(k,50) == 0
			disp('k')
			disp(k)
		end
		z = [acc(k,1:3)'; q_MP(k,:)'; w_MP_gfr__s(k,:)'; acc(k,4:6)'; q_LA(k,:)'; w_LA_gfr__s(k,:)'; acc(k,7:9)'; q_RA(k,:)'; w_RA_gfr__s(k,:)'];
		%could constrain raw measurements here
		
		X = genSig(x,S,mu);                            %sigma points around x
		
		[x1,X_post,Px,X_dev,S] = ut(@f_pvaqw,X,Wm,Wc,L,Q,fs);          %unscented transformation of process
		
		[z1,Z_post,Pz,Z_dev,Sy] = ut(@h_pvaqw,X_post,Wm,Wc,m,R,fs);       %unscented transformation of measurments
		%constrain measuremnts
		Pxz=X_dev*diag(Wc)*Z_dev';                        %transformed cross-covariance
		
		K=(Pxz/Sy)/Sy';
		%K=Pxz/(Pz);
		%     disp('dim K')
		%     disp(size(K));
		%P = Px-K*Pxz';
		% if isConstr
		%         xhat = x1;
		%         options = optimoptions('fmincon','Algorithm','sqp','Display','off',...
		%             'OptimalityTolerance', 1e-4, 'ConstraintTolerance', 1e-4,...
		%             'MaxFunctionEvaluations',15000); % run interior-point algorithm
		%     x1 = fmincon(@(x1) L2Dist(x1,xhat,S),xhat,[],[],[],[],[],[],@(x1) hingeJoint_constrNL_q(x1,...
		%     d_pelvis, d_lfemur, d_rfemur, d_ltibia, d_rtibia),options);
		% end
		x=x1+K*(z-z1);                              %measurement update
		
		if isConstr
			xhat = x;
			options = optimoptions('fmincon','Algorithm','sqp','Display','off',...
				'OptimalityTolerance', 1e-4, 'ConstraintTolerance', 1e-5,...
				'MaxFunctionEvaluations',5000); % run interior-point algorithm
			x = fmincon(@(x) L2Dist(x,xhat,S),xhat,[],[],[],[],[],[],@(x) hingeJoint_constrNL_q(x,...
				d_pelvis, d_lfemur, d_rfemur, d_ltibia, d_rtibia),options);
			
			%         [x] = hingeJoint_constrNL(x,hjc,P,k,q_MP, q_LA, q_RA,...
			%             d_pelvis, d_lfemur, d_rfemur, d_ltibia, d_rtibia);
		end
		U = K*Sy';
		for i = 1:m
			S = cholupdate(S, U(:,i), '-');
		end
		%% gen augmented x return values
		
		%% MR: some recalculation for graphing, variable return/export purposes
		idx_pos_MP = [1:3]';
		idx_vel_MP = [4:6]';
		idx_pos_LA = [17:19]';
		idx_vel_LA = [20:22]';
		idx_pos_RA = [33:35]';
		idx_vel_RA = [36:38]';
		idx_q_MP = [10:13]';
		idx_q_LA = [26:29]';
		idx_q_RA = [42:45]';
		
		
		
		
		LTIB_CS = quat2rotm(x(idx_q_LA)');
		RTIB_CS = quat2rotm(x(idx_q_RA)');
		PELV_CS = quat2rotm(x(idx_q_MP)');
		
		LKNE = x(idx_pos_LA,1) + d_ltibia*LTIB_CS(:,3);
		RKNE = x(idx_pos_RA,1) + d_rtibia*RTIB_CS(:,3);
		LFEP = x(idx_pos_MP,1) + d_pelvis/2*PELV_CS(:,2);
		RFEP = x(idx_pos_MP,1) - d_pelvis/2*PELV_CS(:,2);
		
		LFEM_z = x(idx_pos_MP,1)+d_pelvis/2*PELV_CS(:,2)-LKNE;
		RFEM_z = x(idx_pos_MP,1)-d_pelvis/2*PELV_CS(:,2)-RKNE;
		
		LFEM_z = LFEM_z/norm(LFEM_z);
		RFEM_z = RFEM_z/norm(RFEM_z);
		
		LFEM_z__N = LFEM_z;
		RFEM_z__N = RFEM_z;
		
		% _TIB_CS is _TIB_CS described in wrod frame, or rotm from tib2world frame
		% therefore, inverse is from wrold to tib frame
		LFEM_z__TIB = LTIB_CS\LFEM_z__N;
		RFEM_z__TIB = RTIB_CS\RFEM_z__N;
		
		%global qklVec arkVec
		% alpha_lk = atan2(-LFEM_z__TIB(1), -LFEM_z__TIB(3)) + 0.5*pi;
		% alpha_rk = atan2(-RFEM_z__TIB(1), -RFEM_z__TIB(3)) + 0.5*pi;
		alpha_lk = atan2(-LFEM_z__TIB(3), -LFEM_z__TIB(1)) + 0.5*pi;
		alpha_rk = atan2(-RFEM_z__TIB(3), -RFEM_z__TIB(1)) + 0.5*pi;
		
		qlkVec(k) = alpha_lk;
		qrkVec(k) = alpha_rk;
		LFEM_y = LTIB_CS(:,2);
		RFEM_y = RTIB_CS(:,2);
		
		LFEM_x = cross(LFEM_y,LFEM_z);
		RFEM_x = cross(RFEM_y,RFEM_z);
		
		LFEM_CS = [LFEM_x, LFEM_y, LFEM_z];
		RFEM_CS = [RFEM_x, RFEM_y, RFEM_z];
		
		qLFEM = rotm2quat(LFEM_CS)';
		qRFEM = rotm2quat(RFEM_CS)';
		
		%add pelvis vel-level terms
		l_pel = d_pelvis;
		
		wxPEL = xhat(14);
		wyPEL = xhat(15);
		wzPEL = xhat(16);
		
		q1PEL = xhat(10);
		q2PEL = xhat(11);
		q3PEL = xhat(12);
		q4PEL = xhat(13);
		
		%calc left knee joint angl. vel.
		qLKN = alpha_lk;
		
		wxLTIB = x(30);
		wyLTIB = x(31);
		wzLTIB = x(32);
		
		q1LTIB = x(26);
		q2LTIB = x(27);
		q3LTIB = x(28);
		q4LTIB = x(29);
		
		q1LFEM = qLFEM(1);
		q2LFEM = qLFEM(2);
		q3LFEM = qLFEM(3);
		q4LFEM = qLFEM(4);
		
		wxLFEM = wxLTIB*(4*(q1LFEM*q4LFEM+q2LFEM*q3LFEM)*(q1LTIB*q4LTIB+q2LTIB*q3LTIB)+4*(q1LFEM*q3LFEM-q2LFEM*q4LFEM)*(q1LTIB*q3LTIB-q2LTIB*q4LTIB)+(-1+2*q1LFEM^2+2*q2LFEM^2)*(-1+2*q1LTIB^2+2*q2LTIB^2)) + 2*wyLTIB*((q1LFEM*q4LFEM+q2LFEM*q3LFEM)*(-1+2*q1LTIB^2+2*q3LTIB^2)-2*(q1LTIB*q2LTIB+q3LTIB*q4LTIB)*(q1LFEM*q3LFEM-q2LFEM*q4LFEM)-(q1LTIB*q4LTIB-q2LTIB*q3LTIB)*(-1+2*q1LFEM^2+2*q2LFEM^2)) + 2*wzLTIB*((q1LTIB*q3LTIB+q2LTIB*q4LTIB)*(-1+2*q1LFEM^2+2*q2LFEM^2)-2*(q1LFEM*q4LFEM+q2LFEM*q3LFEM)*(q1LTIB*q2LTIB-q3LTIB*q4LTIB)-(q1LFEM*q3LFEM-q2LFEM*q4LFEM)*(-1+2*q1LTIB^2+2*q4LTIB^2));
		
		wzLFEM = wzLTIB*(4*(q1LFEM*q3LFEM+q2LFEM*q4LFEM)*(q1LTIB*q3LTIB+q2LTIB*q4LTIB)+4*(q1LFEM*q2LFEM-q3LFEM*q4LFEM)*(q1LTIB*q2LTIB-q3LTIB*q4LTIB)+(-1+2*q1LFEM^2+2*q4LFEM^2)*(-1+2*q1LTIB^2+2*q4LTIB^2)) + 2*wxLTIB*((q1LFEM*q3LFEM+q2LFEM*q4LFEM)*(-1+2*q1LTIB^2+2*q2LTIB^2)-2*(q1LTIB*q4LTIB+q2LTIB*q3LTIB)*(q1LFEM*q2LFEM-q3LFEM*q4LFEM)-(q1LTIB*q3LTIB-q2LTIB*q4LTIB)*(-1+2*q1LFEM^2+2*q4LFEM^2)) + 2*wyLTIB*((q1LTIB*q2LTIB+q3LTIB*q4LTIB)*(-1+2*q1LFEM^2+2*q4LFEM^2)-2*(q1LFEM*q3LFEM+q2LFEM*q4LFEM)*(q1LTIB*q4LTIB-q2LTIB*q3LTIB)-(q1LFEM*q2LFEM-q3LFEM*q4LFEM)*(-1+2*q1LTIB^2+2*q3LTIB^2));
		
		wyLFEM = 2*wxLFEM*((q1LTIB*q4LTIB+q2LTIB*q3LTIB)*(-1+2*q1LFEM^2+2*q3LFEM^2)-2*(q1LFEM*q2LFEM+q3LFEM*q4LFEM)*(q1LTIB*q3LTIB-q2LTIB*q4LTIB)-(q1LFEM*q4LFEM-q2LFEM*q3LFEM)*(-1+2*q1LTIB^2+2*q2LTIB^2))/(4*(q1LFEM*q4LFEM+q2LFEM*q3LFEM)*(q1LTIB*q4LTIB+q2LTIB*q3LTIB)+4*(q1LFEM*q3LFEM-q2LFEM*q4LFEM)*(q1LTIB*q3LTIB-q2LTIB*q4LTIB)+(-1+2*q1LFEM^2+2*q2LFEM^2)*(-1+2*q1LTIB^2+2*q2LTIB^2));
		
		qLKN_dot = wyLTIB - wyLFEM;
		
		%---------Trig def of qlkn' results in singularity ----%
		%                 r_LA_LHP = -d_lfemur*cos(alpha_lk)*LTIB_CS(:,3) ...
		%         +d_lfemur*sin(alpha_lk)*LTIB_CS(:,1) ...
		%         -d_ltibia*LTIB_CS(:,3);
		%         dl = norm(r_LA_LHP);
		%         v_LHP_MP__N = PELV_CS*cross([wxPEL; wyPEL; wzPEL],[0; d_pelvis/2; 0]);
		%         dl_dot = dot((xhat(idx_vel_LA)-(xhat(idx_vel_MP) + v_LHP_MP__N)),r_LA_LHP/norm(r_LA_LHP));
		%         Zl = (d_ltibia^2+d_lfemur^2-dl^2)/(2*d_ltibia*d_lfemur);
		%         Zl_dot = (-dl*dl_dot)/(d_ltibia*d_lfemur);
		%         w_LKN_scl = Zl_dot/(1-Zl^2)^(0.5);
		
		%             w_LKN_scl = wyLTIB + 2*(q1LTIB*q4LTIB-q2LTIB*q3LTIB)*(wxLTIB*cos(qLKN)+...
		%         wzLTIB*sin(qLKN))/(2*sin(qLKN)*(q1LTIB*q3LTIB+q2LTIB*q4LTIB)+...
		%         cos(qLKN)*(-1+2*q1LTIB^2+2*q2LTIB^2));
		%
		%calc right knee joint angl. vel.
		qRKN = alpha_rk;
		
		wxRTIB = x(46);
		wyRTIB = x(47);
		wzRTIB = x(48);
		
		q1RTIB = x(42);
		q2RTIB = x(43);
		q3RTIB = x(44);
		q4RTIB = x(45);
		
		q1RFEM = qRFEM(1);
		q2RFEM = qRFEM(2);
		q3RFEM = qRFEM(3);
		q4RFEM = qRFEM(4);
		
		wxRFEM = wxRTIB*(4*(q1RFEM*q4RFEM+q2RFEM*q3RFEM)*(q1RTIB*q4RTIB+q2RTIB*q3RTIB)+4*(q1RFEM*q3RFEM-q2RFEM*q4RFEM)*(q1RTIB*q3RTIB-q2RTIB*q4RTIB)+(-1+2*q1RFEM^2+2*q2RFEM^2)*(-1+2*q1RTIB^2+2*q2RTIB^2)) + 2*wyRTIB*((q1RFEM*q4RFEM+q2RFEM*q3RFEM)*(-1+2*q1RTIB^2+2*q3RTIB^2)-2*(q1RTIB*q2RTIB+q3RTIB*q4RTIB)*(q1RFEM*q3RFEM-q2RFEM*q4RFEM)-(q1RTIB*q4RTIB-q2RTIB*q3RTIB)*(-1+2*q1RFEM^2+2*q2RFEM^2)) + 2*wzRTIB*((q1RTIB*q3RTIB+q2RTIB*q4RTIB)*(-1+2*q1RFEM^2+2*q2RFEM^2)-2*(q1RFEM*q4RFEM+q2RFEM*q3RFEM)*(q1RTIB*q2RTIB-q3RTIB*q4RTIB)-(q1RFEM*q3RFEM-q2RFEM*q4RFEM)*(-1+2*q1RTIB^2+2*q4RTIB^2));
		
		wzRFEM = wzRTIB*(4*(q1RFEM*q3RFEM+q2RFEM*q4RFEM)*(q1RTIB*q3RTIB+q2RTIB*q4RTIB)+4*(q1RFEM*q2RFEM-q3RFEM*q4RFEM)*(q1RTIB*q2RTIB-q3RTIB*q4RTIB)+(-1+2*q1RFEM^2+2*q4RFEM^2)*(-1+2*q1RTIB^2+2*q4RTIB^2)) + 2*wxRTIB*((q1RFEM*q3RFEM+q2RFEM*q4RFEM)*(-1+2*q1RTIB^2+2*q2RTIB^2)-2*(q1RTIB*q4RTIB+q2RTIB*q3RTIB)*(q1RFEM*q2RFEM-q3RFEM*q4RFEM)-(q1RTIB*q3RTIB-q2RTIB*q4RTIB)*(-1+2*q1RFEM^2+2*q4RFEM^2)) + 2*wyRTIB*((q1RTIB*q2RTIB+q3RTIB*q4RTIB)*(-1+2*q1RFEM^2+2*q4RFEM^2)-2*(q1RFEM*q3RFEM+q2RFEM*q4RFEM)*(q1RTIB*q4RTIB-q2RTIB*q3RTIB)-(q1RFEM*q2RFEM-q3RFEM*q4RFEM)*(-1+2*q1RTIB^2+2*q3RTIB^2));
		
		wyRFEM = 2*wxRFEM*((q1RTIB*q4RTIB+q2RTIB*q3RTIB)*(-1+2*q1RFEM^2+2*q3RFEM^2)-2*(q1RFEM*q2RFEM+q3RFEM*q4RFEM)*(q1RTIB*q3RTIB-q2RTIB*q4RTIB)-(q1RFEM*q4RFEM-q2RFEM*q3RFEM)*(-1+2*q1RTIB^2+2*q2RTIB^2))/(4*(q1RFEM*q4RFEM+q2RFEM*q3RFEM)*(q1RTIB*q4RTIB+q2RTIB*q3RTIB)+4*(q1RFEM*q3RFEM-q2RFEM*q4RFEM)*(q1RTIB*q3RTIB-q2RTIB*q4RTIB)+(-1+2*q1RFEM^2+2*q2RFEM^2)*(-1+2*q1RTIB^2+2*q2RTIB^2));
		
		qRKN_dot = wyRTIB - wyRFEM;
		
		%----------- Tirg calc of qrk' results in singularity ----%
		%         r_RA_RHP = -d_rfemur*cos(alpha_rk)*RTIB_CS(:,3) ...
		%         +d_rfemur*sin(alpha_rk)*RTIB_CS(:,1) ...
		%         -d_rtibia*RTIB_CS(:,3);
		%         dr = norm(r_RA_RHP);
		%         v_RHP_MP__N = PELV_CS*cross([wxPEL; wyPEL; wzPEL],[0; -d_pelvis/2; 0]);
		%         dr_dot = dot((xhat(idx_vel_RA)-(xhat(idx_vel_MP) + v_RHP_MP__N)),r_RA_RHP/norm(r_RA_RHP));
		%         Zr = (d_rtibia^2+d_rfemur^2-dr^2)/(2*d_rtibia*d_rfemur);
		%         Zr_dot = (-dr*dr_dot)/(d_rtibia*d_rfemur);
		%         w_RKN_scl = Zr_dot/(1-Zr^2)^(0.5);
		
		%qRKN = -qRKN;
		%w_KN_scl is a scalar value of the knee joint angular velocity
		%     w_RKN_scl = wyRTIB + 2*(q1RTIB*q4RTIB-q2RTIB*q3RTIB)*(wxRTIB*cos(qRKN)+...
		%         wzRTIB*sin(qRKN))/(2*sin(qRKN)*(q1RTIB*q3RTIB+q2RTIB*q4RTIB)+...
		%         cos(qRKN)*(-1+2*q1RTIB^2+2*q2RTIB^2));
		%pelvis(MP)-ankle L2 norm (distance): [est; inst. cent. calc; tru]
		%using tibia and N frames
		%     w_N_RTIB__RTIB = [wxRTIB; wyRTIB; wzRTIB];
		%     w_N_RTIB__N = RTIB_CS*w_N_RTIB__RTIB;
		%     v_RHP_N__N = x(idx_vel_MP) + PELV_CS*cross([wxPEL; wyPEL; wzPEL],[0;-d_pelvis/2;0]);
		%     ICRD_RA = cross(w_N_RTIB__N,v_RHP_N__N)/(dot(w_N_RTIB__N,w_N_RTIB__N));
		%     PAR(:,k) = [norm(x(idx_pos_RA)-x(idx_pos_MP)); ICRD_RA];
		% using tibia and pelvis frames
		w_N_RTIB__RTIB = [wxRTIB; wyRTIB; wzRTIB];
		w_N_RTIB__N = RTIB_CS*w_N_RTIB__RTIB;
		w_N_PEL__N = PELV_CS*[wxPEL;wyPEL;wzPEL];
		w_PEL_RTIB__N = -w_N_PEL__N + w_N_RTIB__N;
		v_RHP_N__N = x(idx_vel_MP) + PELV_CS*cross([wxPEL; wyPEL; wzPEL],[0;-d_pelvis/2;0]);
		v_RA_RHP__N = x(idx_vel_RA) - v_RHP_N__N;
		ICRD_RA = cross(w_PEL_RTIB__N,v_RA_RHP__N)/(dot(w_PEL_RTIB__N,w_PEL_RTIB__N));
		PAR(:,k) = [norm(x(idx_pos_RA)-x(idx_pos_MP)); ICRD_RA];
		x_rec(:,k) = x;
		xa_rec(:,k) = [LFEP; LKNE; RFEP; RKNE];
		qFEM(:,k) = [qLFEM; qRFEM];
		w_KN(:,k) = [qLKN_dot; qRKN_dot];
	end
end

function [x1,X_post,Px,X_dev,S]=ut(g,X,Wm,Wc,nStates,Q,fs)
	%Unscented propogation Transformation
	%Input:
	%        g: nonlinear map
	%        X: sigma points
	%       Wm: weights for mean
	%       Wc: weights for covraiance
	%        n: number of outputs of f
	%        Q: additive covariance
	%       fs: sampleing frequency
	%Output:
	%        x1: transformed mean
	%    X_post: transformed smapling points
	%        Px: transformed covariance
	%     X_dev: transformed deviations
	%         S: "square root" of covariance (col. factor)

	L = size(X,2);
	x1 = zeros(nStates,1); % mean of state x
	X_post = zeros(nStates,L);
	for k=1:L
		X_post(:,k)=g(X(:,k),fs);
		x1=x1+Wm(k)*X_post(:,k);
	end
	X_dev=X_post-x1(:,ones(1,L));
	Px=X_dev*diag(Wc)*X_dev'+Q;
	A_tmp = [sqrt(Wc(2))*(X_post(:,2:L)-x1) sqrt(Q)]'; % square root UKF, append Q instead of add Q
	if issparse(A_tmp)
		S = qr(A_tmp,0);
	else
		S = triu(qr(A_tmp,0));
	end
	
	S = S(1:length(x1),1:length(x1)); % this step shouldn't be necessary. It was put in place to ensure correct dimentionanilty of matrix S
	if Wc(1) < 0
		S = cholupdate(S, (X_post(:,1)-x1), '-');
	else
		S = cholupdate(S, (X_post(:,1)-x1), '+');
	end
end

function X=genSig(x,S,mu)
	%Sigma points symetrically distributed around initial point
	%Inputs:
	%       x: reference point
	%       P: covariance
	%       mu: coefficient
	%Output:
	%       X: Sigma points

	% A = mu*chol(P)'; %cholesky factorization
	Y = x(:,ones(1,length(x)));
	X = [x Y+mu*S' Y-mu*S'];
end
%for state vec with pos vel accel, quat, ang.vel
function [xp] = f_pvaqw(x,fs)
	dt = 1/fs;
	dt2 = 1/2*(1/fs)^2;
	As(1:3,:) = [eye(3,3) dt*eye(3,3) dt2*eye(3,3) zeros(3,7)];
	As(4:6,:) = [zeros(3,3) eye(3,3) dt*eye(3,3) zeros(3,7)];
	As(7:9,:) = [zeros(3,6) eye(3,3) zeros(3,7)];
	As(10:16,:) = [zeros(7,9) eye(7,7)];
	Af = [As zeros(16,32); zeros(16,16) As zeros(16,16); zeros(16,32) As];
	xp = Af*x;
	%mp
	e0 = xp(10); e1 = xp(11); e2 = xp(12); e3 = xp(13);
	epm = [-e1 -e2 -e3;...
		e0 -e3 e2;...
		e3 e0 -e1;...
		-e2 e1 e0];
	xp(10:13) = xp(10:13) + 0.5*epm*xp(14:16)*dt;
	%LA
	e0 = xp(26); e1 = xp(27); e2 = xp(28); e3 = xp(29);
	epm = [-e1 -e2 -e3;...
		e0 -e3 e2;...
		e3 e0 -e1;...
		-e2 e1 e0];
	xp(26:29) = xp(26:29) + 0.5*epm*xp(30:32)*dt;
	%RA
	e0 = xp(42); e1 = xp(43); e2 = xp(44); e3 = xp(45);
	epm = [-e1 -e2 -e3;...
		e0 -e3 e2;...
		e3 e0 -e1;...
		-e2 e1 e0];
	xp(42:45) = xp(42:45) + 0.5*epm*xp(46:48)*dt;
end

%for state vec with pos vel accel, quat, ang.vel
function [hp] = h_pvaqw(x,fs)
	Hs(1:3,:) = [zeros(3,6) eye(3,3) zeros(3,7)]; % acceleration measurement update
	Hs(4:7,:) = [zeros(4,9) eye(4,4) zeros(4,3)]; % quaternion measurement update
	Hs(8:10,:) = [zeros(3,13) eye(3,3)]; % angular velocity measurement update
	Hf = [Hs zeros(10,32); zeros(10,16) Hs zeros(10,16); zeros(10,32) Hs];
	hp = Hf*x;
end

function y = L2Dist(x,x0,S)
	%x^2 is monotomically increasing at any point not at 0, so traditional
	%L2 norm involving sqrt is unnecessary, can use x^2 to find same
	%location of min cost in constrained region with less computational
	%cost.
	%using inverse of covariance rather than I will make state est over time
	%less smooth but more accurate over the average of the interval

	%y = (x-x0)'*(x-x0);
	% add index specifying pos. of mp la and ra rather than including q
	qW = 1;%norm(x0); %weighting for q deviation to account for diffin units between pos and q.
	% posW = 100;
	% velW = 0.00001;
	posW = 10;
	velW = 1;
	%need to adapt x to rel pos of LA and RA to prevent large data recording
	%problems
	%posIdx = [];
	res = (x-x0);
	qIdx = [10:13 26:29 42:45]';
	posIdx = [1:3 17:19 33:35]';
	velIdx = [4:6 20:22 36:38]';
	res(qIdx) = qW*res(qIdx);
	res(posIdx) = posW*res(posIdx);
	res(velIdx) = velW*res(velIdx);
	%res = S\res; %add res*inv(S) to scale cost by certainty
	%n = 1000000; %have also tried 2,4,6,8,14,16,100,1000 around >= 14 greatly increases speed of finding solution, not much difference etween 100 and 1000
	n = 1000;

	%y = sqrt((res'*res));

	y = sum(res.^n)^(1/n);
end

function [c, ceq] = hingeJoint_constrNL_q(xhat,...
    d_pelvis, d_lfemur, d_rfemur, d_ltibia, d_rtibia)
	%% Pos-level knee joint constraint
	idx_pos_MP = [1:3]';
	idx_pos_LA = [17:19]';
	idx_pos_RA = [33:35]';

	idx_vel_MP = [4:6]';
	idx_vel_LA = [20:22]';
	idx_vel_RA = [36:38]';

	idx_q_MP = [10:13]';
	idx_q_LA = [26:29]';
	idx_q_RA = [42:45]';

	idx_w_MP = [14:16]';
	idx_w_LA = [30:32]';
	idx_w_RA = [46:48]';

	I_N = eye(length(xhat));
	%       pos     vel         accel       quat    ang.vel      pos     vel         accel       quat    ang.vel        pos     vel         accel       quat    ang.vel
	D = [-eye(3,3) zeros(3,3) zeros(3,3) zeros(3,4) zeros(3,3) eye(3,3) zeros(3,3) zeros(3,3) zeros(3,4) zeros(3,3) zeros(3,3) zeros(3,3) zeros(3,3) zeros(3,4) zeros(3,3);
		-eye(3,3) zeros(3,3) zeros(3,3) zeros(3,4) zeros(3,3) zeros(3,3) zeros(3,3) zeros(3,3) zeros(3,4) zeros(3,3) eye(3,3) zeros(3,3) zeros(3,3) zeros(3,4)  zeros(3,3)];

	%rotate from sensor to gfr frame
	LTIB_CS = quat2rotm(xhat(idx_q_LA,1)');
	RTIB_CS = quat2rotm(xhat(idx_q_RA,1)');
	PELV_CS = quat2rotm(xhat(idx_q_MP,1)');


	LKNE = xhat(idx_pos_LA,1) + d_ltibia*LTIB_CS(:,3);
	RKNE = xhat(idx_pos_RA,1) + d_rtibia*RTIB_CS(:,3);

	% calculate the z axis of the femur
	LFEM_z = xhat(idx_pos_MP,1)+d_pelvis/2*PELV_CS(:,2)-LKNE;
	RFEM_z = xhat(idx_pos_MP,1)-d_pelvis/2*PELV_CS(:,2)-RKNE;

	% normalize z-axis of femur
	LFEM_z = LFEM_z/norm(LFEM_z);
	RFEM_z = RFEM_z/norm(RFEM_z);

	% calculate the z axis of the tibia
	LTIB_z = LTIB_CS(:,3);
	RTIB_z = RTIB_CS(:,3);

	% calculate alpha_lk and alpha_rk
	%alpha_lk = acos(dot(LFEM_z, LTIB_z)/(norm(LFEM_z)*norm(LTIB_z)));
	%alpha_rk = acos(dot(RFEM_z, RTIB_z)/(norm(RFEM_z)*norm(RTIB_z)));

	%calculate alpha_lk and alpha_rk using atan2
	LFEM_z__N = LFEM_z;
	RFEM_z__N = RFEM_z;

	% _TIB_CS is _TIB_CS described in world frame, or rotm from tib2world frame
	% therefore, inverse is from wrold to tib frame
	LFEM_z__TIB = LTIB_CS\LFEM_z__N;
	RFEM_z__TIB = RTIB_CS\RFEM_z__N;

	%global alpha_lk alpha_rk
	% alpha_lk = atan2(-LFEM_z__TIB(1), -LFEM_z__TIB(3)) + 0.5*pi;
	% alpha_rk = atan2(-RFEM_z__TIB(1), -RFEM_z__TIB(3)) + 0.5*pi;
	alpha_lk = atan2(-LFEM_z__TIB(3), -LFEM_z__TIB(1)) + 0.5*pi;
	alpha_rk = atan2(-RFEM_z__TIB(3), -RFEM_z__TIB(1)) + 0.5*pi;

	% setup the constraint equations
	d_k = [ (d_pelvis/2*PELV_CS(:,2) ...
		-d_lfemur*cos(alpha_lk)*LTIB_CS(:,3) ...
		+d_lfemur*sin(alpha_lk)*LTIB_CS(:,1) ...
		-d_ltibia*LTIB_CS(:,3)) ; ...
		(-d_pelvis/2*PELV_CS(:,2)+ ...
		-d_rfemur*cos(alpha_rk)*RTIB_CS(:,3) ...
		+d_rfemur*sin(alpha_rk)*RTIB_CS(:,1) ...
		-d_rtibia*RTIB_CS(:,3)) ];

	LFEM_y = LTIB_CS(:,2);
	RFEM_y = RTIB_CS(:,2);

	LFEM_x = cross(LFEM_y,LFEM_z);
	RFEM_x = cross(RFEM_y,RFEM_z);

	LFEM_CS = [LFEM_x, LFEM_y, LFEM_z];
	RFEM_CS = [RFEM_x, RFEM_y, RFEM_z];

	qLFEM = rotm2quat(LFEM_CS)';
	qRFEM = rotm2quat(RFEM_CS)';

	%% MG-generated Pos constraint
	%     q1PEL = xhat(10);
	%     q2PEL = xhat(11);
	%     q3PEL = xhat(12);
	%     q4PEL = xhat(13);
	%
	%     q1LTIB = xhat(26);
	%     q2LTIB = xhat(27);
	%     q3LTIB = xhat(28);
	%     q4LTIB = xhat(29);
	%
	%     q1RTIB = xhat(42);
	%     q2RTIB = xhat(43);
	%     q3RTIB = xhat(44);
	%     q4RTIB = xhat(45);
	%
	%     qLKN = alpha_lk;
	%     qRKN = alpha_rk;
	%
	%  p_LTIBo_PELo =[(-2*d_ltibia*(q1LTIB*q3LTIB+q2LTIB*q4LTIB)-d_pelvis*(q1PEL*q4PEL-q2PEL*q3PEL)...
	% -d_lfemur*(2*cos(qLKN)*(q1LTIB*q3LTIB+q2LTIB*q4LTIB)-sin(qLKN)*(-1+2*q1LTIB^2+2*q2LTIB^2)));...
	%  + (2*d_ltibia*(q1LTIB*q2LTIB-q3LTIB*q4LTIB)+0.5*d_pelvis*(-1+2*q1PEL^2+2*q3PEL^2)...
	%  +2*d_lfemur*(sin(qLKN)*(q1LTIB*q4LTIB+q2LTIB*q3LTIB)+cos(qLKN)*(q1LTIB*q2LTIB-q3LTIB*q4LTIB)));...
	%  + (d_pelvis*(q1PEL*q2PEL+q3PEL*q4PEL)-d_ltibia*(-1+2*q1LTIB^2+2*q4LTIB^2)...
	%  -d_lfemur*(2*sin(qLKN)*(q1LTIB*q3LTIB-q2LTIB*q4LTIB)+cos(qLKN)*(-1+2*q1LTIB^2+2*q4LTIB^2)))];
	% %
	%   p_RTIBo_PELo = [(d_pelvis*(q1PEL*q4PEL-q2PEL*q3PEL)-2*d_rtibia*(q1RTIB*q3RTIB+q2RTIB*q4RTIB)...
	%       -d_rfemur*(2*cos(qRKN)*(q1RTIB*q3RTIB+q2RTIB*q4RTIB)-sin(qRKN)*(-1+2*q1RTIB^2+2*q2RTIB^2)));...
	%       + (2*d_rtibia*(q1RTIB*q2RTIB-q3RTIB*q4RTIB)+2*d_rfemur*(sin(qRKN)*(q1RTIB*q4RTIB+q2RTIB*q3RTIB)...
	%       +cos(qRKN)*(q1RTIB*q2RTIB-q3RTIB*q4RTIB))-0.5*d_pelvis*(-1+2*q1PEL^2+2*q3PEL^2));...
	%       + (-d_pelvis*(q1PEL*q2PEL+q3PEL*q4PEL)-d_rtibia*(-1+2*q1RTIB^2+2*q4RTIB^2)...
	%       -d_rfemur*(2*sin(qRKN)*(q1RTIB*q3RTIB-q2RTIB*q4RTIB)+cos(qRKN)*(-1+2*q1RTIB^2+2*q4RTIB^2)))];
	%  d_k = [p_LTIBo_PELo;
	%         p_RTIBo_PELo];
	%% Vel-Level Knee-Joint Constraint
	%% Variable assignment based on knee cosntructing constraints
	%(left or right knee)

	l_pel = d_pelvis;

	wxPEL = xhat(14);
	wyPEL = xhat(15);
	wzPEL = xhat(16);

	q1PEL = xhat(10);
	q2PEL = xhat(11);
	q3PEL = xhat(12);
	q4PEL = xhat(13);


	dxv = [xhat(20) - xhat(4); %left ankle_pel rel vel in Nx
		xhat(21) - xhat(5); % || in Ny
		xhat(22) - xhat(6);%  || in Nz
		xhat(36) - xhat(4);% right ankle _pel rel vel in Nx
		xhat(37) - xhat(5);%    || Ny
		xhat(38) - xhat(6)];%   || Nz

	%% left knee

	%         l_tib = d_ltibia;
	%         l_fem = d_lfemur;

	qLKN = alpha_lk;

	wxLTIB = xhat(30);
	wyLTIB = xhat(31);
	wzLTIB = xhat(32);

	q1LTIB = xhat(26);
	q2LTIB = xhat(27);
	q3LTIB = xhat(28);
	q4LTIB = xhat(29);

	q1LFEM = qLFEM(1);
	q2LFEM = qLFEM(2);
	q3LFEM = qLFEM(3);
	q4LFEM = qLFEM(4);

	%vector diff form
	grlib.est.genLAMPRelVel_v4
	%relVel_LANK_PELo_N = -relVel_LANK_PELo_N;
	%---Trig differentiation, results in singularity---%
	%         r_LA_MP = xhat(idx_pos_LA) - xhat(idx_pos_MP);
	%         r_LA_LHP = -d_lfemur*cos(alpha_lk)*LTIB_CS(:,3) ...
	%         +d_lfemur*sin(alpha_lk)*LTIB_CS(:,1) ...
	%         -d_ltibia*LTIB_CS(:,3);
	%         dl = norm(r_LA_LHP);
	%         %dl = norm(xhat(idx_pos_LA)-xhat(idx_pos_MP));
	%         v_LHP_MP__N = PELV_CS*cross([wxPEL; wyPEL; wzPEL],[0; d_pelvis/2; 0]);
	%         dl_dot = dot((xhat(idx_vel_LA)-(xhat(idx_vel_MP)+v_LHP_MP__N)),r_LA_LHP/norm(r_LA_LHP));
	%         Zl = (d_ltibia^2+d_lfemur^2-dl^2)/(2*d_ltibia*d_lfemur);
	%         Zl_dot = (-dl*dl_dot)/(d_ltibia*d_lfemur);
	%w_LKN_scl = Zl_dot/(1-Zl^2)^(0.5);

	%              w_LKN_scl = wyLTIB + 2*(q1LTIB*q4LTIB-q2LTIB*q3LTIB)*(wxLTIB*cos(qLKN)+...
	%         wzLTIB*sin(qLKN))/(2*sin(qLKN)*(q1LTIB*q3LTIB+q2LTIB*q4LTIB)+...
	%         cos(qLKN)*(-1+2*q1LTIB^2+2*q2LTIB^2));

	%w_KN_scl = -w_KN_scl;
	%relVel_ANK_PELo_N is the relative velocities of the ankle from the pelvis,
	%described in frame N (eqivalent to gfr)

	%gen std vel. eq.
	%grlib.est.genLAMPRelVel_v2

	%manually generate rel vel from mp (diff pos-level pin joint eq)
	%grlib.est.genLAMPRelVel_v3

	%Golden Rule Differentiation
	%     relVel_LANK_PELo_N = PELV_CS*cross([wxPEL;wyPEL;wzPEL],[0; d_pelvis/2; 0])...
	%         -LTIB_CS*cross(([wxLTIB; wyLTIB; wzLTIB]+[0; w_LKN_scl; 0]),[0;0;d_lfemur])...
	%         -LTIB_CS*cross([wxLTIB; wyLTIB; wzLTIB],[0;0;d_ltibia]);
	%
	%gen manual velocity eq
	%grlib.est.genLAMPRelVel

	d_k_v(1:3,1) = relVel_LANK_PELo_N;

	%% right knee
	%         l_tib = d_rtibia;
	%         l_fem = d_rfemur;

	qRKN = alpha_rk;

	wxRTIB = xhat(46);
	wyRTIB = xhat(47);
	wzRTIB = xhat(48);

	q1RTIB = xhat(42);
	q2RTIB = xhat(43);
	q3RTIB = xhat(44);
	q4RTIB = xhat(45);

	q1RFEM = qRFEM(1);
	q2RFEM = qRFEM(2);
	q3RFEM = qRFEM(3);
	q4RFEM = qRFEM(4);

	%vector diff form
	grlib.est.genRAMPRelVel_v4
	%relVel_RANK_PELo_N = -relVel_RANK_PELo_N;
	%-------------Trig diff results insinguarity-----%
	%     r_RA_RHP = -d_rfemur*cos(alpha_rk)*RTIB_CS(:,3) ...
	%         +d_rfemur*sin(alpha_rk)*RTIB_CS(:,1) ...
	%         -d_rtibia*RTIB_CS(:,3);
	%         dr = norm(r_RA_RHP);
	%         %dr = norm(xhat(idx_pos_RA)-xhat(idx_pos_MP));
	%         v_RHP_MP__N = PELV_CS*cross([wxPEL; wyPEL; wzPEL],[0; -d_pelvis/2; 0]);
	%         dr_dot = dot((xhat(idx_vel_RA)-(xhat(idx_vel_MP) + v_RHP_MP__N)),r_RA_RHP/norm(r_RA_RHP));
	%         Zr = (d_rtibia^2+d_rfemur^2-dr^2)/(2*d_rtibia*d_rfemur);
	%         Zr_dot = (-dr*dr_dot)/(d_rtibia*d_rfemur);
	%         w_RKN_scl = Zr_dot/(1-Zr^2)^(0.5);
	%
	%qRKN = -qRKN;
	%w_KN_scl is a scalar value of the knee joint angular velocity
	%w_RKN_scl = wyRTIB + 2*(q1RTIB*q4RTIB-q2RTIB*q3RTIB)*(wxRTIB*cos(qRKN)+...
	%         wzRTIB*sin(qRKN))/(2*sin(qRKN)*(q1RTIB*q3RTIB+q2RTIB*q4RTIB)+...
	%         cos(qRKN)*(-1+2*q1RTIB^2+2*q2RTIB^2));
	%w_RKN_scl = -w_RKN_scl;
	%relVel_ANK_PELo_N is the relative velocities of the ankle from the pelvis,
	%described in frame N (eqivalent to gfr)

	%gen std. vel. from MP
	%grlib.est.genRAMPRelVel_v2

	%manual generate rel vel from MP
	%grlib.est.genRAMPRelVel_v3

	%Golden Rule Differentiation
	%     relVel_RANK_PELo_N = PELV_CS*cross([wxPEL;wyPEL;wzPEL],[0; -d_pelvis/2; 0])...
	%         -RTIB_CS*cross(([wxRTIB; wyRTIB; wzRTIB]+[0; w_RKN_scl; 0]),[0;0;d_rfemur])...
	%         -RTIB_CS*cross([wxRTIB; wyRTIB; wzRTIB],[0;0;d_rtibia]);
	%
	%gen right ankle rel vel from MP
	%grlib.est.genRAMPRelVel
	d_k_v(4:6,1) = relVel_RANK_PELo_N;


	%% construct constraint for fmincon format
	% res = d_k - D*xhat;
	% ceq = res'*res;
	kv = 1;
	pRes = (d_k - D*xhat);
	vRes = (d_k_v - dxv);

	kq = 1;
	qMPRes = (xhat(idx_q_MP)'*xhat(idx_q_MP))-1;
	qLARes = (xhat(idx_q_LA)'*xhat(idx_q_LA))-1;
	qRARes = (xhat(idx_q_RA)'*xhat(idx_q_RA))-1;

	qDotMP = calcqdot(xhat(idx_q_MP),xhat(idx_w_MP));
	qDotMPRes = xhat(idx_q_MP)'*qDotMP;
	qDotLA = calcqdot(xhat(idx_q_LA),xhat(idx_w_LA));
	qDotLARes = xhat(idx_q_LA)'*qDotLA;
	qDotRA = calcqdot(xhat(idx_q_RA),xhat(idx_w_RA));
	qDotRARes = xhat(idx_q_RA)'*qDotRA;
	%constrain augmented qFem, wFem

	qLFEMRes = qLFEM'*qLFEM - 1;
	qRFEMRes = qRFEM'*qRFEM - 1;

	qDotLFEM = calcqdot(qLFEM,[wxLFEM;wyLFEM;wzLFEM]);
	qDotLFEMRes = qDotLFEM'*qDotLFEM;
	qDotRFEM = calcqdot(qRFEM,[wxRFEM;wyRFEM;wzRFEM]);
	qDotRFEMRes = qDotRFEM'*qDotRFEM;

	%ceq = [ pRes;
	ceq = [ pRes;
		kq*qMPRes; % added to make sure the state is a proper quaternion
		kq*qLARes;
		kq*qRARes;
		kq*qDotMPRes;
		kq*qDotLARes;
		kq*qDotRARes];
	%         kq*qLFEMRes;
	%         kq*qDotLFEMRes;
	%         kq*qRFEMRes;
	%         kq*qDotRFEMRes];


	maxFootVel = 10; %m/s
	maxKNAngVel = 10; %rad/s
	% c = [norm(xhat(idx_vel_LA))-maxFootVel;
	%     norm(xhat(idx_vel_RA))-maxFootVel];
	qSafetyFactor = deg2rad(3);
	%c = [];
	c = [-(alpha_lk-deg2rad(2));
		(alpha_lk+deg2rad(20)) - pi;
		-(alpha_rk-deg2rad(2));
		(alpha_rk+deg2rad(20)) - pi;
		abs(qLKN_dot) - maxKNAngVel;
		abs(qRKN_dot) - maxKNAngVel;
		norm(relVel_LANK_PELo_N) - maxFootVel;
		norm(relVel_RANK_PELo_N) - maxFootVel];
	%knee joint angular velocity cap from :
	%Effects of power training on muscle structure and neuromuscular performance
	%March 2005Scandinavian Journal of Medicine and Science in Sports 15(1):58-64

	%TODO (or at least consider):
	% add quaternion constraints (accel) as in 331 text (MR: doesn't matter, don't do it - 21 Jun 2018)
	% add accel-level knee-joint constraint  (MR: doesn't matter, don't do it - 21 Jun 2018)
	% Tune weighting on pos-vel knee constraints (kv)  (MR: doesn't matter, don't do it - 21 Jun 2018)
	% add additional physiological params (ang vel, etc.)  (MR: doesn't matter, don't do it - 21 Jun 2018)
	% Add ZVUPT
	% Add trailing accel rec, to limit jerk profile->smooth/limit accel  (MR: doesn't matter, don't do it - 21 Jun 2018)
end

function qdot = calcqdot(q,w)
	e0 = q(1); e1 = q(2); e2 = q(3); e3 = q(4);
	epm = [-e1 -e2 -e3;...
		e0 -e3 e2;...
		e3 e0 -e1;...
		-e2 e1 e0];
	qdot = 0.5*epm*w;
end