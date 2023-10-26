function mpc = Systeminfo
%CASE9    Power flow data for 9 bus, 3 generator case.
%   Please see CASEFORMAT for details on the case file format.
%
%   Based on data from p. 70 of:
%
%   Chow, J. H., editor. Time-Scale Modeling of Dynamic Networks with
%   Applications to Power Systems. Springer-Verlag, 1982.
%   Part of the Lecture Notes in Control and Information Sciences book
%   series (LNCIS, volume 46)
%8
%   which in turn appears to come from:
%
%   R.P. Schulz, A.E. Turner and D.N. Ewart, "Long Term Power System
%   Dynamics," EPRI Report 90-7-0, Palo Alto, California, 1974.

%   MATPOWER

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	3	0	0	0	0	1	1	0	345	1	1.1	0.9;
	2	2	0	0	0	0	1	1	0	345	1	1.1	0.9;
	3	2	0	0	0	0	1	1	0	345	1	1.1	0.9;
	4	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	5	1	300	98	0	0	1	1	0	345	1	1.1	0.9;
	6	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	7	1	400	98	0	0	1	1	0	345	1	1.1	0.9;
	8	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	9	1	400	131	0	0	1	1	0	345	1	1.1	0.9;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status      Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [  
1	0	0	30	-30	1	100	1	55	8	0	0	0	0	0	0	0	0	0	0	0	;	%1,Coal1
1	0	0	30	-30	1	100	1	55	17	0	0	0	0	0	0	0	0	0	0	0	;	%2,Coal2
1	0	0	30	-30	1	100	1	70	18	0	0	0	0	0	0	0	0	0	0	0	;	%3,Coal3
2	0	0	30	-30	1	100	1	70	16	0	0	0	0	0	0	0	0	0	0	0	;	%4,Coal4
3	0	0	30	-30	1	100	1	80	39	0	0	0	0	0	0	0	0	0	0	0	;	%5,Coal5
3	0	0	30	-30	1	100	1	90	38	0	0	0	0	0	0	0	0	0	0	0	;	%6,Coal6
2   0	0	30	-30	1	100	1	45	19	0	0	0	0	0	0	0	0	0	0	0	;	%7,CC1
3	0	0	30	-30	1	100	1	50	27	0	0	0	0	0	0	0	0	0	0	0	;	%8,CC2
2	0	0	30	-30	1	100	1	75	41	0	0	0	0	0	0	0	0	0	0	0	;	%9,CC3
1	0	0	30	-30	1	100	1	35	30	0	0	0	0	0	0	0	0	0	0	0	;	%10,CT1
1	0	0	30	-30	1	100	1	35	29	0	0	0	0	0	0	0	0	0	0	0	;	%11,CT2
2	0	0	30	-30	1	100	1	35	31	0	0	0	0	0	0	0	0	0	0	0	;	%12,CT3
3	0	0	30	-30	1	100	1	40	12	0	0	0	0	0	0	0	0	0	0	0	;	%13,CT4
3	0	0	30	-30	1	100	1	40	12	0	0	0	0	0	0	0	0	0	0	0	;	%14,CT5
2	0	0	30	-30	1	100	1	55	25	0	0	0	0	0	0	0	0	0	0	0	;	%15,CT6
2	0	0	30	-30	1	100	1	20	15	0	0	0	0	0	0	0	0	0	0	0	;	%16,oil
2	0	0	30	-30	1	100	1	0	0	0	0	0	0	0	0	0	0	0	0	0		%17,RE
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	4	0       0.0576	0       1000	250	250	0	0	1	-360	360;
	4	5	0.017	0.092	0.158	1000	250	250	0	0	1	-360	360;
	5	6	0.039	0.17	0.358	1000	150	150	0	0	1	-360	360;
	3	6	0       0.0586	0       1000	300	300	0	0	1	-360	360;
	6	7	0.0119	0.1008	0.209	1000	200	200	0	0	1	-360	360;
	7	8	0.0085	0.072	0.149	1000	250	250	0	0	1	-360	360;
	8	2	0       0.0625	0       1000	300	300	0	0	1	-360	360;
	8	9	0.032	0.161	0.306	1000	250	250	0	0	1	-360	360;
	9	4	0.01	0.085	0.176	1000	250	250	0	0	1	-360	360;
];

%%-----  OPF Data  -----%%
%% generator cost data
%	1	startup	shutdown	n	x1	y1	...	xn	yn
%	2	startup	shutdown	n	c(n-1)	...	c0
mpc.gencost = [										
2	0	0	3	0.053977059	7.232230688	84.5;           
2	0	0	3	0.025023111	8.5	        70.35021639	;           
2	0	0	3	0.015119153	8.901715908	74.01758158	;
2	0	0	3	0.035793963	7.546297721	55.20741353	;
2	0	0	3	0.00869709	6.854698668	120.8743898	;
2	0	0	3	1.00E-08	8.397713552	75.97502234	;
2	0	0	3	0.075635376	4.15	    88.29564486 ;      
2	0	0	3	0.001860025	6.301343243	110.4719341	;
2	0	0	3	0.010624362	5.436829397	110.8971692	;
2	0	0	3	1.00E-08	9.612095796	-0.794007121;
2	0	0	3	1.00E-08	9.587906631	1.34837787	;
2	0	0	3	1.00E-08	8.435895781	5.53187415	;
2	0	0	3	1.00E-08	10.70078118	-13.64386393;	
2	0	0	3	1.00E-08	7.578918265	60.22375666	;
2	0	0	3	1.00E-08	9.87	    2.01	    ;          
2	0	0	3	0.00000001	5.870854867	72.06392537 ;
2	0	0	3	1e-12	    1e-12	    1e-12          
];
