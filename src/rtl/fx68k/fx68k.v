module fx68k (
	clk,
	HALTn,
	extReset,
	pwrUp,
	enPhi1,
	enPhi2,
	eRWn,
	ASn,
	LDSn,
	UDSn,
	E,
	VMAn,
	FC0,
	FC1,
	FC2,
	BGn,
	oRESETn,
	oHALTEDn,
	DTACKn,
	VPAn,
	BERRn,
	BRn,
	BGACKn,
	IPL0n,
	IPL1n,
	IPL2n,
	iEdb,
	oEdb,
	eab
);
	reg _sv2v_0;
	input clk;
	input HALTn;
	input extReset;
	input pwrUp;
	input enPhi1;
	input enPhi2;
	output wire eRWn;
	output wire ASn;
	output wire LDSn;
	output wire UDSn;
	output reg E;
	output wire VMAn;
	output wire FC0;
	output wire FC1;
	output wire FC2;
	output wire BGn;
	output wire oRESETn;
	output wire oHALTEDn;
	input DTACKn;
	input VPAn;
	input BERRn;
	input BRn;
	input BGACKn;
	input IPL0n;
	input IPL1n;
	input IPL2n;
	input [15:0] iEdb;
	output wire [15:0] oEdb;
	output wire [23:1] eab;
	wire [4:0] Clks;
	assign Clks[4] = clk;
	assign Clks[3] = extReset;
	assign Clks[2] = pwrUp;
	assign Clks[1] = enPhi1;
	assign Clks[0] = enPhi2;
	wire wClk;
	reg [31:0] tState;
	wire enT1 = (Clks[1] & (tState == 32'd4)) & ~wClk;
	wire enT2 = Clks[0] & (tState == 32'd1);
	wire enT3 = Clks[1] & (tState == 32'd2);
	wire enT4 = Clks[0] & ((tState == 32'd0) | (tState == 32'd3));
	always @(posedge Clks[4])
		if (Clks[2])
			tState <= 32'd0;
		else
			case (tState)
				32'd0:
					if (Clks[0])
						tState <= 32'd4;
				32'd1:
					if (Clks[0])
						tState <= 32'd2;
				32'd2:
					if (Clks[1])
						tState <= 32'd3;
				32'd3:
					if (Clks[0])
						tState <= 32'd4;
				32'd4:
					if (Clks[1])
						tState <= (wClk ? 32'd0 : 32'd1);
			endcase
	reg rDtack;
	reg rBerr;
	reg [2:0] rIpl;
	reg [2:0] iIpl;
	reg Vpai;
	reg BeI;
	reg Halti;
	reg BRi;
	reg BgackI;
	reg BeiDelay;
	wire BeDebounced = ~(BeI | BeiDelay);
	always @(posedge Clks[4])
		if (Clks[2]) begin
			rBerr <= 1'b0;
			BeI <= 1'b0;
		end
		else if (Clks[0]) begin
			rDtack <= DTACKn;
			rBerr <= BERRn;
			rIpl <= ~{IPL2n, IPL1n, IPL0n};
			iIpl <= rIpl;
		end
		else if (Clks[1]) begin
			Vpai <= VPAn;
			BeI <= rBerr;
			BeiDelay <= BeI;
			BgackI <= BGACKn;
			BRi <= BRn;
			Halti <= HALTn;
		end
	localparam NANO_WIDTH = 68;
	reg [67:0] nanoLatch;
	wire [67:0] nanoOutput;
	localparam UROM_WIDTH = 17;
	reg [16:0] microLatch;
	wire [16:0] microOutput;
	localparam UADDR_WIDTH = 10;
	reg [9:0] microAddr;
	wire [9:0] nma;
	localparam NADDR_WIDTH = 9;
	reg [8:0] nanoAddr;
	wire [8:0] orgAddr;
	wire rstUrom;
	microToNanoAddr microToNanoAddr(
		.uAddr(nma),
		.orgAddr(orgAddr)
	);
	nanoRom nanoRom(
		.clk(Clks[4]),
		.nanoAddr(nanoAddr),
		.nanoOutput(nanoOutput)
	);
	uRom uRom(
		.clk(Clks[4]),
		.microAddr(microAddr),
		.microOutput(microOutput)
	);
	localparam RSTP0_NMA = 'h2;
	always @(posedge Clks[4]) begin
		if (Clks[2]) begin
			microAddr <= RSTP0_NMA;
			nanoAddr <= RSTP0_NMA;
		end
		else if (enT1) begin
			microAddr <= nma;
			nanoAddr <= orgAddr;
		end
		if (Clks[3]) begin
			microLatch <= 1'sb0;
			nanoLatch <= 1'sb0;
		end
		else if (rstUrom) begin
			{microLatch[16], microLatch[15], microLatch[0]} <= 1'sb0;
			nanoLatch <= 1'sb0;
		end
		else if (enT3) begin
			microLatch <= microOutput;
			nanoLatch <= nanoOutput;
		end
	end
	wire [104:0] Nanod;
	wire [41:0] Irdecod;
	reg Tpend;
	reg intPend;
	reg pswT;
	reg pswS;
	reg [2:0] pswI;
	wire [7:0] ccr;
	wire [15:0] psw = {pswT, 1'b0, pswS, 2'b00, pswI, ccr};
	reg [15:0] ftu;
	reg [15:0] Irc;
	reg [15:0] Ir;
	reg [15:0] Ird;
	wire [15:0] alue;
	wire [15:0] Abl;
	wire prenEmpty;
	wire au05z;
	wire dcr4;
	wire ze;
	wire [9:0] a1;
	wire [9:0] a2;
	wire [9:0] a3;
	wire isPriv;
	wire isIllegal;
	wire isLineA;
	wire isLineF;
	always @(posedge Clks[4])
		if (enT1) begin
			if (Nanod[81])
				Ird <= Ir;
			else if (microLatch[0])
				Ir <= Irc;
		end
	wire [3:0] tvn;
	wire waitBusCycle;
	wire busStarting;
	wire BusRetry = 1'b0;
	wire busAddrErr;
	wire bciWrite;
	wire bgBlock;
	wire busAvail;
	wire addrOe;
	wire busIsByte = Nanod[101] & (Irdecod[32] | Irdecod[31]);
	wire aob0;
	reg iStop;
	reg A0Err;
	reg excRst;
	reg BerrA;
	reg Spuria;
	reg Avia;
	wire Iac;
	reg rAddrErr;
	reg iBusErr;
	reg Err6591;
	wire iAddrErr = rAddrErr & addrOe;
	wire enErrClk;
	assign rstUrom = Clks[1] & enErrClk;
	uaddrDecode uaddrDecode(
		.opcode(Ir),
		.a1(a1),
		.a2(a2),
		.a3(a3),
		.isPriv(isPriv),
		.isIllegal(isIllegal),
		.isLineA(isLineA),
		.isLineF(isLineF),
		.lineBmap()
	);
	sequencer sequencer(
		.Clks(Clks),
		.enT3(enT3),
		.microLatch(microLatch),
		.Ird(Ird),
		.A0Err(A0Err),
		.excRst(excRst),
		.BerrA(BerrA),
		.busAddrErr(busAddrErr),
		.Spuria(Spuria),
		.Avia(Avia),
		.Tpend(Tpend),
		.intPend(intPend),
		.isIllegal(isIllegal),
		.isPriv(isPriv),
		.isLineA(isLineA),
		.isLineF(isLineF),
		.nma(nma),
		.a1(a1),
		.a2(a2),
		.a3(a3),
		.tvn(tvn),
		.psw(psw),
		.prenEmpty(prenEmpty),
		.au05z(au05z),
		.dcr4(dcr4),
		.ze(ze),
		.alue01(alue[1:0]),
		.i11(Irc[11])
	);
	wire [16:1] sv2v_tmp_excUnit_Irc;
	always @(*) Irc = sv2v_tmp_excUnit_Irc;
	excUnit excUnit(
		.Clks(Clks),
		.Nanod(Nanod),
		.Irdecod(Irdecod),
		.enT1(enT1),
		.enT2(enT2),
		.enT3(enT3),
		.enT4(enT4),
		.Ird(Ird),
		.ftu(ftu),
		.iEdb(iEdb),
		.pswS(pswS),
		.prenEmpty(prenEmpty),
		.au05z(au05z),
		.dcr4(dcr4),
		.ze(ze),
		.AblOut(Abl),
		.eab(eab),
		.aob0(aob0),
		.Irc(sv2v_tmp_excUnit_Irc),
		.oEdb(oEdb),
		.alue(alue),
		.ccr(ccr)
	);
	nDecoder3 nDecoder(
		.Clks(Clks),
		.Nanod(Nanod),
		.Irdecod(Irdecod),
		.enT2(enT2),
		.enT4(enT4),
		.microLatch(microLatch),
		.nanoLatch(nanoLatch)
	);
	irdDecode irdDecode(
		.ird(Ird),
		.Irdecod(Irdecod)
	);
	busControl busControl(
		.Clks(Clks),
		.enT1(enT1),
		.enT4(enT4),
		.permStart(Nanod[104]),
		.permStop(Nanod[103]),
		.iStop(iStop),
		.aob0(aob0),
		.isWrite(Nanod[102]),
		.isRmc(Nanod[100]),
		.isByte(busIsByte),
		.busAvail(busAvail),
		.bciWrite(bciWrite),
		.addrOe(addrOe),
		.bgBlock(bgBlock),
		.waitBusCycle(waitBusCycle),
		.busStarting(busStarting),
		.busAddrErr(busAddrErr),
		.rDtack(rDtack),
		.BeDebounced(BeDebounced),
		.Vpai(Vpai),
		.ASn(ASn),
		.LDSn(LDSn),
		.UDSn(UDSn),
		.eRWn(eRWn)
	);
	busArbiter busArbiter(
		.Clks(Clks),
		.BRi(BRi),
		.BgackI(BgackI),
		.Halti(Halti),
		.bgBlock(bgBlock),
		.busAvail(busAvail),
		.BGn(BGn)
	);
	wire [1:0] uFc = microLatch[16:15];
	reg oReset;
	reg oHalted;
	assign oRESETn = !oReset;
	assign oHALTEDn = !oHalted;
	always @(posedge Clks[4])
		if (Clks[2]) begin
			oReset <= 1'b0;
			oHalted <= 1'b0;
		end
		else if (enT1) begin
			oReset <= (uFc == 2'b01) & !Nanod[104];
			oHalted <= (uFc == 2'b10) & !Nanod[104];
		end
	reg [2:0] rFC;
	assign {FC2, FC1, FC0} = rFC;
	assign Iac = {rFC == 3'b111};
	always @(posedge Clks[4])
		if (Clks[3])
			rFC <= 1'sb0;
		else if (enT1 & Nanod[104]) begin
			rFC[2] <= pswS;
			rFC[1] <= microLatch[16] | (~microLatch[15] & Irdecod[41]);
			rFC[0] <= microLatch[15] | (~microLatch[16] & ~Irdecod[41]);
		end
	reg [2:0] inl;
	reg updIll;
	reg prevNmi;
	wire nmi = iIpl == 3'b111;
	wire iplStable = iIpl == rIpl;
	wire iplComp = iIpl > pswI;
	always @(posedge Clks[4]) begin
		if (Clks[3]) begin
			intPend <= 1'b0;
			prevNmi <= 1'b0;
		end
		else begin
			if (Clks[0])
				prevNmi <= nmi;
			if (Clks[0]) begin
				if (iplStable & ((nmi & ~prevNmi) | iplComp))
					intPend <= 1'b1;
				else if (((inl == 3'b111) & Iac) | ((iplStable & !nmi) & !iplComp))
					intPend <= 1'b0;
			end
		end
		if (Clks[3]) begin
			inl <= 1'sb1;
			updIll <= 1'b0;
		end
		else if (enT4)
			updIll <= microLatch[0];
		else if (enT1 & updIll)
			inl <= iIpl;
		if (enT4) begin
			Spuria <= ~BeiDelay & Iac;
			Avia <= ~Vpai & Iac;
		end
	end
	assign enErrClk = iAddrErr | iBusErr;
	assign wClk = ((waitBusCycle | ~BeI) | iAddrErr) | Err6591;
	reg [3:0] eCntr;
	reg rVma;
	assign VMAn = rVma;
	wire xVma = ~rVma & (eCntr == 8);
	always @(posedge Clks[4]) begin
		if (Clks[2]) begin
			E <= 1'b0;
			eCntr <= 1'sb0;
			rVma <= 1'b1;
		end
		if (Clks[0]) begin
			if (eCntr == 9)
				E <= 1'b0;
			else if (eCntr == 5)
				E <= 1'b1;
			if (eCntr == 9)
				eCntr <= 1'sb0;
			else
				eCntr <= eCntr + 1'b1;
		end
		if (((Clks[0] & addrOe) & ~Vpai) & (eCntr == 3))
			rVma <= 1'b0;
		else if (Clks[1] & (eCntr == {4 {1'sb0}}))
			rVma <= 1'b1;
	end
	always @(posedge Clks[4]) begin
		if (Clks[3])
			rAddrErr <= 1'b0;
		else if (Clks[1]) begin
			if (busAddrErr & addrOe)
				rAddrErr <= 1'b1;
			else if (~addrOe)
				rAddrErr <= 1'b0;
		end
		if (Clks[3])
			iBusErr <= 1'b0;
		else if (Clks[1])
			iBusErr <= ((BerrA & ~BeI) & ~Iac) & !BusRetry;
		if (Clks[3])
			BerrA <= 1'b0;
		else if (Clks[0]) begin
			if ((~BeI & ~Iac) & addrOe)
				BerrA <= 1'b1;
			else if (BeI & busStarting)
				BerrA <= 1'b0;
		end
		if (Clks[3])
			excRst <= 1'b1;
		else if (enT2 & Nanod[104])
			excRst <= 1'b0;
		if (Clks[3])
			A0Err <= 1'b1;
		else if (enT3)
			A0Err <= 1'b0;
		else if ((Clks[1] & enErrClk) & (busAddrErr | BerrA))
			A0Err <= 1'b1;
		if (Clks[3]) begin
			iStop <= 1'b0;
			Err6591 <= 1'b0;
		end
		else if (Clks[1])
			Err6591 <= enErrClk;
		else if (Clks[0])
			iStop <= xVma | (Vpai & (iAddrErr | ~rBerr));
	end
	reg irdToCcr_t4;
	always @(posedge Clks[4])
		if (Clks[2]) begin
			Tpend <= 1'b0;
			{pswT, pswS, pswI} <= 1'sb0;
			irdToCcr_t4 <= 1'sb0;
		end
		else if (enT4)
			irdToCcr_t4 <= Irdecod[38];
		else if (enT3) begin
			if (Nanod[97])
				Tpend <= pswT;
			else if (Nanod[96])
				Tpend <= 1'b0;
			if (Nanod[88] & !irdToCcr_t4)
				{pswT, pswS, pswI} <= {ftu[15], ftu[13], ftu[10:8]};
			else begin
				if (Nanod[82]) begin
					pswS <= 1'b1;
					pswT <= 1'b0;
				end
				if (Nanod[89])
					pswI <= inl;
			end
		end
	reg [4:0] ssw;
	reg [3:0] tvnLatch;
	reg [15:0] tvnMux;
	reg inExcept01;
	always @(posedge Clks[4]) begin
		if (Nanod[61] & enT3)
			ssw <= {~bciWrite, inExcept01, rFC};
		if (enT1 & Nanod[81]) begin
			tvnLatch <= tvn;
			inExcept01 <= tvn != 1;
		end
		if (Clks[2])
			ftu <= 1'sb0;
		else if (enT3)
			(* full_case, parallel_case *)
			case (1'b1)
				Nanod[95]: ftu <= tvnMux;
				Nanod[87]: ftu <= {pswT, 1'b0, pswS, 2'b00, pswI, 3'b000, ccr[4:0]};
				Nanod[84]: ftu <= Ird;
				Nanod[83]: ftu[4:0] <= ssw;
				Nanod[85]: ftu <= {12'hfff, pswI, 1'b0};
				Nanod[94]: ftu <= Irdecod[22-:16];
				Nanod[91]: ftu <= Abl;
				default: ftu <= ftu;
			endcase
	end
	localparam TVN_AUTOVEC = 13;
	localparam TVN_INTERRUPT = 15;
	localparam TVN_SPURIOUS = 12;
	always @(*) begin
		if (_sv2v_0)
			;
		if (inExcept01) begin
			if (tvnLatch == TVN_SPURIOUS)
				tvnMux = 16'h0060;
			else if (tvnLatch == TVN_AUTOVEC)
				tvnMux = {11'b00000000011, pswI, 2'b00};
			else if (tvnLatch == TVN_INTERRUPT)
				tvnMux = {6'b000000, Ird[7:0], 2'b00};
			else
				tvnMux = {10'b0000000000, tvnLatch, 2'b00};
		end
		else
			tvnMux = {8'h00, Irdecod[6-:6], 2'b00};
	end
	initial _sv2v_0 = 0;
endmodule
module nDecoder3 (
	Clks,
	Irdecod,
	Nanod,
	enT2,
	enT4,
	microLatch,
	nanoLatch
);
	input wire [4:0] Clks;
	input wire [41:0] Irdecod;
	output reg [104:0] Nanod;
	input enT2;
	input enT4;
	localparam UROM_WIDTH = 17;
	input [16:0] microLatch;
	localparam NANO_WIDTH = 68;
	input [67:0] nanoLatch;
	localparam NANO_IR2IRD = 67;
	localparam NANO_TOIRC = 66;
	localparam NANO_ALU_COL = 63;
	localparam NANO_ALU_FI = 61;
	localparam NANO_TODBIN = 60;
	localparam NANO_ALUE = 57;
	localparam NANO_DCR = 57;
	localparam NANO_DOBCTRL_1 = 56;
	localparam NANO_LOWBYTE = 55;
	localparam NANO_HIGHBYTE = 54;
	localparam NANO_DOBCTRL_0 = 53;
	localparam NANO_ALU_DCTRL = 51;
	localparam NANO_ALU_ACTRL = 50;
	localparam NANO_DBD2ALUB = 49;
	localparam NANO_ABD2ALUB = 48;
	localparam NANO_DBIN2DBD = 47;
	localparam NANO_DBIN2ABD = 46;
	localparam NANO_ALU2ABD = 45;
	localparam NANO_ALU2DBD = 44;
	localparam NANO_RZ = 43;
	localparam NANO_BUSBYTE = 42;
	localparam NANO_PCLABL = 41;
	localparam NANO_RXL_DBL = 40;
	localparam NANO_PCLDBL = 39;
	localparam NANO_ABDHRECHARGE = 38;
	localparam NANO_REG2ABL = 37;
	localparam NANO_ABL2REG = 36;
	localparam NANO_ABLABD = 35;
	localparam NANO_DBLDBD = 34;
	localparam NANO_DBL2REG = 33;
	localparam NANO_REG2DBL = 32;
	localparam NANO_ATLCTRL = 29;
	localparam NANO_FTUCONTROL = 25;
	localparam NANO_SSP = 24;
	localparam NANO_RXH_DBH = 22;
	localparam NANO_AUOUT = 20;
	localparam NANO_AUCLKEN = 19;
	localparam NANO_AUCTRL = 16;
	localparam NANO_DBLDBH = 15;
	localparam NANO_ABLABH = 14;
	localparam NANO_EXT_ABH = 13;
	localparam NANO_EXT_DBH = 12;
	localparam NANO_ATHCTRL = 9;
	localparam NANO_REG2ABH = 8;
	localparam NANO_ABH2REG = 7;
	localparam NANO_REG2DBH = 6;
	localparam NANO_DBH2REG = 5;
	localparam NANO_AOBCTRL = 3;
	localparam NANO_PCH = 0;
	localparam NANO_NO_SP_ALGN = 0;
	localparam NANO_FTU_UPDTPEND = 1;
	localparam NANO_FTU_INIT_ST = 15;
	localparam NANO_FTU_CLRTPEND = 14;
	localparam NANO_FTU_TVN = 13;
	localparam NANO_FTU_ABL2PREN = 12;
	localparam NANO_FTU_SSW = 11;
	localparam NANO_FTU_RSTPREN = 10;
	localparam NANO_FTU_IRD = 9;
	localparam NANO_FTU_2ABL = 8;
	localparam NANO_FTU_RDSR = 7;
	localparam NANO_FTU_INL = 6;
	localparam NANO_FTU_PSWI = 5;
	localparam NANO_FTU_DBL = 4;
	localparam NANO_FTU_2SR = 2;
	localparam NANO_FTU_CONST = 1;
	reg [3:0] ftuCtrl;
	wire [2:0] athCtrl;
	wire [2:0] atlCtrl;
	assign athCtrl = nanoLatch[11:NANO_ATHCTRL];
	assign atlCtrl = nanoLatch[31:NANO_ATLCTRL];
	wire [1:0] aobCtrl = nanoLatch[4:NANO_AOBCTRL];
	wire [1:0] dobCtrl = {nanoLatch[NANO_DOBCTRL_1], nanoLatch[NANO_DOBCTRL_0]};
	always @(posedge Clks[4])
		if (enT4) begin
			ftuCtrl <= {nanoLatch[25], nanoLatch[26], nanoLatch[27], nanoLatch[28]};
			Nanod[80] <= !nanoLatch[NANO_AUCLKEN];
			Nanod[78-:3] <= nanoLatch[18:16];
			Nanod[79] <= nanoLatch[1:NANO_NO_SP_ALGN] == 2'b11;
			Nanod[6] <= nanoLatch[NANO_EXT_DBH];
			Nanod[5] <= nanoLatch[NANO_EXT_ABH];
			Nanod[75] <= nanoLatch[NANO_TODBIN];
			Nanod[74] <= nanoLatch[NANO_TOIRC];
			Nanod[4] <= nanoLatch[NANO_ABLABD];
			Nanod[3] <= nanoLatch[NANO_ABLABH];
			Nanod[2] <= nanoLatch[NANO_DBLDBD];
			Nanod[1] <= nanoLatch[NANO_DBLDBH];
			Nanod[73] <= atlCtrl == 3'b010;
			Nanod[70] <= atlCtrl == 3'b011;
			Nanod[72] <= atlCtrl == 3'b100;
			Nanod[71] <= atlCtrl == 3'b101;
			Nanod[62] <= athCtrl == 3'b101;
			Nanod[69] <= (athCtrl == 3'b001) | (athCtrl == 3'b101);
			Nanod[68] <= athCtrl == 3'b100;
			Nanod[67] <= athCtrl == 3'b110;
			Nanod[66] <= athCtrl == 3'b011;
			Nanod[13] <= nanoLatch[NANO_ALU2DBD];
			Nanod[12] <= nanoLatch[NANO_ALU2ABD];
			Nanod[19] <= nanoLatch[58:NANO_DCR] == 2'b11;
			Nanod[18] <= nanoLatch[59:58] == 2'b11;
			Nanod[17] <= nanoLatch[59:58] == 2'b10;
			Nanod[16] <= nanoLatch[58:NANO_ALUE] == 2'b01;
			Nanod[15] <= nanoLatch[NANO_DBD2ALUB];
			Nanod[14] <= nanoLatch[NANO_ABD2ALUB];
			Nanod[60-:2] <= dobCtrl;
		end
	wire [1:1] sv2v_tmp_AE35E;
	assign sv2v_tmp_AE35E = Nanod[62];
	always @(*) Nanod[61] = sv2v_tmp_AE35E;
	wire [1:1] sv2v_tmp_A4BAF;
	assign sv2v_tmp_A4BAF = ftuCtrl == NANO_FTU_UPDTPEND;
	always @(*) Nanod[97] = sv2v_tmp_A4BAF;
	wire [1:1] sv2v_tmp_CF9F2;
	assign sv2v_tmp_CF9F2 = ftuCtrl == NANO_FTU_CLRTPEND;
	always @(*) Nanod[96] = sv2v_tmp_CF9F2;
	wire [1:1] sv2v_tmp_923B0;
	assign sv2v_tmp_923B0 = ftuCtrl == NANO_FTU_TVN;
	always @(*) Nanod[95] = sv2v_tmp_923B0;
	wire [1:1] sv2v_tmp_F8CCE;
	assign sv2v_tmp_F8CCE = ftuCtrl == NANO_FTU_CONST;
	always @(*) Nanod[94] = sv2v_tmp_F8CCE;
	wire [1:1] sv2v_tmp_05D12;
	assign sv2v_tmp_05D12 = (ftuCtrl == NANO_FTU_DBL) | (ftuCtrl == NANO_FTU_INL);
	always @(*) Nanod[93] = sv2v_tmp_05D12;
	wire [1:1] sv2v_tmp_BD2E1;
	assign sv2v_tmp_BD2E1 = ftuCtrl == NANO_FTU_2ABL;
	always @(*) Nanod[92] = sv2v_tmp_BD2E1;
	wire [1:1] sv2v_tmp_B47FA;
	assign sv2v_tmp_B47FA = ftuCtrl == NANO_FTU_INL;
	always @(*) Nanod[89] = sv2v_tmp_B47FA;
	wire [1:1] sv2v_tmp_F1A47;
	assign sv2v_tmp_F1A47 = ftuCtrl == NANO_FTU_PSWI;
	always @(*) Nanod[85] = sv2v_tmp_F1A47;
	wire [1:1] sv2v_tmp_3B5A3;
	assign sv2v_tmp_3B5A3 = ftuCtrl == NANO_FTU_2SR;
	always @(*) Nanod[88] = sv2v_tmp_3B5A3;
	wire [1:1] sv2v_tmp_DF1EF;
	assign sv2v_tmp_DF1EF = ftuCtrl == NANO_FTU_RDSR;
	always @(*) Nanod[87] = sv2v_tmp_DF1EF;
	wire [1:1] sv2v_tmp_4FFD3;
	assign sv2v_tmp_4FFD3 = ftuCtrl == NANO_FTU_IRD;
	always @(*) Nanod[84] = sv2v_tmp_4FFD3;
	wire [1:1] sv2v_tmp_1799C;
	assign sv2v_tmp_1799C = ftuCtrl == NANO_FTU_SSW;
	always @(*) Nanod[83] = sv2v_tmp_1799C;
	wire [1:1] sv2v_tmp_08C5E;
	assign sv2v_tmp_08C5E = ((ftuCtrl == NANO_FTU_INL) | (ftuCtrl == NANO_FTU_CLRTPEND)) | (ftuCtrl == NANO_FTU_INIT_ST);
	always @(*) Nanod[82] = sv2v_tmp_08C5E;
	wire [1:1] sv2v_tmp_B6A07;
	assign sv2v_tmp_B6A07 = ftuCtrl == NANO_FTU_ABL2PREN;
	always @(*) Nanod[91] = sv2v_tmp_B6A07;
	wire [1:1] sv2v_tmp_99F51;
	assign sv2v_tmp_99F51 = ftuCtrl == NANO_FTU_RSTPREN;
	always @(*) Nanod[90] = sv2v_tmp_99F51;
	wire [1:1] sv2v_tmp_64EE2;
	assign sv2v_tmp_64EE2 = nanoLatch[NANO_IR2IRD];
	always @(*) Nanod[81] = sv2v_tmp_64EE2;
	wire [2:1] sv2v_tmp_065F0;
	assign sv2v_tmp_065F0 = nanoLatch[52:NANO_ALU_DCTRL];
	always @(*) Nanod[24-:2] = sv2v_tmp_065F0;
	wire [1:1] sv2v_tmp_65B25;
	assign sv2v_tmp_65B25 = nanoLatch[NANO_ALU_ACTRL];
	always @(*) Nanod[22] = sv2v_tmp_65B25;
	wire [3:1] sv2v_tmp_EF868;
	assign sv2v_tmp_EF868 = {nanoLatch[NANO_ALU_COL], nanoLatch[64], nanoLatch[65]};
	always @(*) Nanod[27-:3] = sv2v_tmp_EF868;
	wire [1:0] aluFinInit = nanoLatch[62:NANO_ALU_FI];
	wire [1:1] sv2v_tmp_A7F1C;
	assign sv2v_tmp_A7F1C = aluFinInit == 2'b10;
	always @(*) Nanod[20] = sv2v_tmp_A7F1C;
	wire [1:1] sv2v_tmp_E29FD;
	assign sv2v_tmp_E29FD = aluFinInit == 2'b01;
	always @(*) Nanod[21] = sv2v_tmp_E29FD;
	wire [1:1] sv2v_tmp_00B71;
	assign sv2v_tmp_00B71 = aluFinInit == 2'b11;
	always @(*) Nanod[86] = sv2v_tmp_00B71;
	wire [1:1] sv2v_tmp_CF9FA;
	assign sv2v_tmp_CF9FA = nanoLatch[NANO_ABDHRECHARGE];
	always @(*) Nanod[0] = sv2v_tmp_CF9FA;
	wire [1:1] sv2v_tmp_D4347;
	assign sv2v_tmp_D4347 = nanoLatch[21:NANO_AUOUT] == 2'b01;
	always @(*) Nanod[11] = sv2v_tmp_D4347;
	wire [1:1] sv2v_tmp_AF0C6;
	assign sv2v_tmp_AF0C6 = nanoLatch[21:NANO_AUOUT] == 2'b10;
	always @(*) Nanod[10] = sv2v_tmp_AF0C6;
	wire [1:1] sv2v_tmp_C978E;
	assign sv2v_tmp_C978E = nanoLatch[21:NANO_AUOUT] == 2'b11;
	always @(*) Nanod[9] = sv2v_tmp_C978E;
	wire [1:1] sv2v_tmp_76F18;
	assign sv2v_tmp_76F18 = aobCtrl == 2'b10;
	always @(*) Nanod[65] = sv2v_tmp_76F18;
	wire [1:1] sv2v_tmp_707E9;
	assign sv2v_tmp_707E9 = aobCtrl == 2'b01;
	always @(*) Nanod[64] = sv2v_tmp_707E9;
	wire [1:1] sv2v_tmp_69D9F;
	assign sv2v_tmp_69D9F = aobCtrl == 2'b11;
	always @(*) Nanod[63] = sv2v_tmp_69D9F;
	wire [1:1] sv2v_tmp_D0FD0;
	assign sv2v_tmp_D0FD0 = nanoLatch[NANO_DBIN2ABD];
	always @(*) Nanod[8] = sv2v_tmp_D0FD0;
	wire [1:1] sv2v_tmp_039CA;
	assign sv2v_tmp_039CA = nanoLatch[NANO_DBIN2DBD];
	always @(*) Nanod[7] = sv2v_tmp_039CA;
	wire [1:1] sv2v_tmp_1712D;
	assign sv2v_tmp_1712D = |aobCtrl;
	always @(*) Nanod[104] = sv2v_tmp_1712D;
	wire [1:1] sv2v_tmp_C45EE;
	assign sv2v_tmp_C45EE = |dobCtrl;
	always @(*) Nanod[102] = sv2v_tmp_C45EE;
	wire [1:1] sv2v_tmp_C294B;
	assign sv2v_tmp_C294B = (nanoLatch[NANO_TOIRC] | nanoLatch[NANO_TODBIN]) | Nanod[102];
	always @(*) Nanod[103] = sv2v_tmp_C294B;
	wire [1:1] sv2v_tmp_FF015;
	assign sv2v_tmp_FF015 = nanoLatch[NANO_BUSBYTE];
	always @(*) Nanod[101] = sv2v_tmp_FF015;
	wire [1:1] sv2v_tmp_213A2;
	assign sv2v_tmp_213A2 = nanoLatch[NANO_LOWBYTE];
	always @(*) Nanod[99] = sv2v_tmp_213A2;
	wire [1:1] sv2v_tmp_19F6E;
	assign sv2v_tmp_19F6E = nanoLatch[NANO_HIGHBYTE];
	always @(*) Nanod[98] = sv2v_tmp_19F6E;
	wire [1:1] sv2v_tmp_4C783;
	assign sv2v_tmp_4C783 = nanoLatch[NANO_ABL2REG];
	always @(*) Nanod[57] = sv2v_tmp_4C783;
	wire [1:1] sv2v_tmp_D06B8;
	assign sv2v_tmp_D06B8 = nanoLatch[NANO_ABH2REG];
	always @(*) Nanod[58] = sv2v_tmp_D06B8;
	wire [1:1] sv2v_tmp_B5A52;
	assign sv2v_tmp_B5A52 = nanoLatch[NANO_DBL2REG];
	always @(*) Nanod[53] = sv2v_tmp_B5A52;
	wire [1:1] sv2v_tmp_FFA61;
	assign sv2v_tmp_FFA61 = nanoLatch[NANO_DBH2REG];
	always @(*) Nanod[54] = sv2v_tmp_FFA61;
	wire [1:1] sv2v_tmp_CF423;
	assign sv2v_tmp_CF423 = nanoLatch[NANO_REG2DBL];
	always @(*) Nanod[52] = sv2v_tmp_CF423;
	wire [1:1] sv2v_tmp_62454;
	assign sv2v_tmp_62454 = nanoLatch[NANO_REG2DBH];
	always @(*) Nanod[51] = sv2v_tmp_62454;
	wire [1:1] sv2v_tmp_1D2B2;
	assign sv2v_tmp_1D2B2 = nanoLatch[NANO_REG2ABL];
	always @(*) Nanod[56] = sv2v_tmp_1D2B2;
	wire [1:1] sv2v_tmp_8B945;
	assign sv2v_tmp_8B945 = nanoLatch[NANO_REG2ABH];
	always @(*) Nanod[55] = sv2v_tmp_8B945;
	wire [1:1] sv2v_tmp_10BC5;
	assign sv2v_tmp_10BC5 = nanoLatch[NANO_SSP];
	always @(*) Nanod[50] = sv2v_tmp_10BC5;
	wire [1:1] sv2v_tmp_8D9D2;
	assign sv2v_tmp_8D9D2 = nanoLatch[NANO_RZ];
	always @(*) Nanod[29] = sv2v_tmp_8D9D2;
	wire dtldbd = 1'b0;
	wire dthdbh = 1'b0;
	wire dtlabd = 1'b0;
	wire dthabh = 1'b0;
	wire dblSpecial = Nanod[48] | dtldbd;
	wire dbhSpecial = Nanod[49] | dthdbh;
	wire ablSpecial = Nanod[47] | dtlabd;
	wire abhSpecial = Nanod[46] | dthabh;
	wire [1:1] sv2v_tmp_E99A5;
	assign sv2v_tmp_E99A5 = nanoLatch[NANO_RXL_DBL];
	always @(*) Nanod[28] = sv2v_tmp_E99A5;
	wire isPcRel = Irdecod[41] & !Nanod[29];
	wire pcRelDbl = isPcRel & !nanoLatch[NANO_RXL_DBL];
	wire pcRelDbh = isPcRel & !nanoLatch[NANO_RXH_DBH];
	wire pcRelAbl = isPcRel & nanoLatch[NANO_RXL_DBL];
	wire pcRelAbh = isPcRel & nanoLatch[NANO_RXH_DBH];
	wire [1:1] sv2v_tmp_4D805;
	assign sv2v_tmp_4D805 = nanoLatch[NANO_PCLDBL] | pcRelDbl;
	always @(*) Nanod[48] = sv2v_tmp_4D805;
	wire [1:1] sv2v_tmp_07CE8;
	assign sv2v_tmp_07CE8 = (nanoLatch[1:NANO_PCH] == 2'b01) | pcRelDbh;
	always @(*) Nanod[49] = sv2v_tmp_07CE8;
	wire [1:1] sv2v_tmp_A385A;
	assign sv2v_tmp_A385A = nanoLatch[NANO_PCLABL] | pcRelAbl;
	always @(*) Nanod[47] = sv2v_tmp_A385A;
	wire [1:1] sv2v_tmp_3D902;
	assign sv2v_tmp_3D902 = (nanoLatch[1:NANO_PCH] == 2'b10) | pcRelAbh;
	always @(*) Nanod[46] = sv2v_tmp_3D902;
	always @(posedge Clks[4]) begin
		if (enT4) begin
			Nanod[41] <= (Nanod[52] & !dblSpecial) & nanoLatch[NANO_RXL_DBL];
			Nanod[40] <= (Nanod[56] & !ablSpecial) & !nanoLatch[NANO_RXL_DBL];
			Nanod[43] <= (Nanod[53] & !dblSpecial) & nanoLatch[NANO_RXL_DBL];
			Nanod[39] <= (Nanod[57] & !ablSpecial) & !nanoLatch[NANO_RXL_DBL];
			Nanod[45] <= (Nanod[51] & !dbhSpecial) & nanoLatch[NANO_RXH_DBH];
			Nanod[44] <= (Nanod[55] & !abhSpecial) & !nanoLatch[NANO_RXH_DBH];
			Nanod[42] <= (Nanod[54] & !dbhSpecial) & nanoLatch[NANO_RXH_DBH];
			Nanod[38] <= (Nanod[58] & !abhSpecial) & !nanoLatch[NANO_RXH_DBH];
			Nanod[37] <= (Nanod[54] & !dbhSpecial) & !nanoLatch[NANO_RXH_DBH];
			Nanod[36] <= (Nanod[58] & !abhSpecial) & nanoLatch[NANO_RXH_DBH];
			Nanod[31] <= (Nanod[53] & !dblSpecial) & !nanoLatch[NANO_RXL_DBL];
			Nanod[30] <= (Nanod[57] & !ablSpecial) & nanoLatch[NANO_RXL_DBL];
			Nanod[35] <= (Nanod[52] & !dblSpecial) & !nanoLatch[NANO_RXL_DBL];
			Nanod[34] <= (Nanod[56] & !ablSpecial) & nanoLatch[NANO_RXL_DBL];
			Nanod[33] <= (Nanod[51] & !dbhSpecial) & !nanoLatch[NANO_RXH_DBH];
			Nanod[32] <= (Nanod[55] & !abhSpecial) & nanoLatch[NANO_RXH_DBH];
		end
		if (enT4)
			Nanod[100] <= Irdecod[40] & nanoLatch[NANO_BUSBYTE];
	end
endmodule
module irdDecode (
	ird,
	Irdecod
);
	reg _sv2v_0;
	input [15:0] ird;
	output reg [41:0] Irdecod;
	wire [3:0] line = ird[15:12];
	wire [15:0] lineOnehot;
	onehotEncoder4 irdLines(
		.bin(line),
		.bitMap(lineOnehot)
	);
	wire isRegShift = lineOnehot['he] & (ird[7:6] != 2'b11);
	wire isDynShift = isRegShift & ird[5];
	wire [1:1] sv2v_tmp_9D785;
	assign sv2v_tmp_9D785 = ((&ird[5:3] & ~isDynShift) & !ird[2]) & ird[1];
	always @(*) Irdecod[41] = sv2v_tmp_9D785;
	wire [1:1] sv2v_tmp_1BD44;
	assign sv2v_tmp_1BD44 = lineOnehot[4] & (ird[11:6] == 6'b101011);
	always @(*) Irdecod[40] = sv2v_tmp_1BD44;
	wire [3:1] sv2v_tmp_C005B;
	assign sv2v_tmp_C005B = ird[11:9];
	always @(*) Irdecod[30-:3] = sv2v_tmp_C005B;
	wire [3:1] sv2v_tmp_603B5;
	assign sv2v_tmp_603B5 = ird[2:0];
	always @(*) Irdecod[27-:3] = sv2v_tmp_603B5;
	wire isPreDecr = ird[5:3] == 3'b100;
	wire eaAreg = ird[5:3] == 3'b001;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (1'b1)
			lineOnehot[1], lineOnehot[2], lineOnehot[3]: Irdecod[24] = |ird[8:6];
			lineOnehot[4]: Irdecod[24] = &ird[8:6];
			lineOnehot['h8]: Irdecod[24] = (eaAreg & ird[8]) & ~ird[7];
			lineOnehot['hc]: Irdecod[24] = (eaAreg & ird[8]) & ~ird[7];
			lineOnehot['h9], lineOnehot['hb], lineOnehot['hd]: Irdecod[24] = (ird[7] & ird[6]) | ((eaAreg & ird[8]) & (ird[7:6] != 2'b11));
			default: Irdecod[24] = Irdecod[39];
		endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		Irdecod[34] = (lineOnehot[4] & ~ird[8]) & ~Irdecod[39];
	end
	wire [1:1] sv2v_tmp_2D301;
	assign sv2v_tmp_2D301 = Irdecod[34] & isPreDecr;
	always @(*) Irdecod[33] = sv2v_tmp_2D301;
	wire [1:1] sv2v_tmp_40C9E;
	assign sv2v_tmp_40C9E = lineOnehot[5] | (lineOnehot[0] & ~ird[8]);
	always @(*) Irdecod[37] = sv2v_tmp_40C9E;
	wire [1:1] sv2v_tmp_26777;
	assign sv2v_tmp_26777 = lineOnehot[4] & (ird[11:4] == 8'he6);
	always @(*) Irdecod[35] = sv2v_tmp_26777;
	wire eaImmOrAbs = (ird[5:3] == 3'b111) & ~ird[1];
	wire [1:1] sv2v_tmp_E109D;
	assign sv2v_tmp_E109D = eaImmOrAbs & ~isRegShift;
	always @(*) Irdecod[36] = sv2v_tmp_E109D;
	always @(*) begin : sv2v_autoblock_1
		reg eaIsAreg;
		if (_sv2v_0)
			;
		eaIsAreg = (ird[5:3] != 3'b000) & (ird[5:3] != 3'b111);
		(* full_case, parallel_case *)
		case (1'b1)
			default: Irdecod[23] = eaIsAreg;
			lineOnehot[5]: Irdecod[23] = eaIsAreg & (ird[7:3] != 5'b11001);
			lineOnehot[6], lineOnehot[7]: Irdecod[23] = 1'b0;
			lineOnehot['he]: Irdecod[23] = ~isRegShift;
		endcase
	end
	wire xIsScc = (ird[7:6] == 2'b11) & (ird[5:3] != 3'b001);
	wire xStaticMem = (ird[11:8] == 4'b1000) & (ird[5:4] == 2'b00);
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (1'b1)
			lineOnehot[0]: Irdecod[32] = (((ird[8] & (ird[5:4] != 2'b00)) | ((ird[11:8] == 4'b1000) & (ird[5:4] != 2'b00))) | ((ird[8:7] == 2'b10) & (ird[5:3] == 3'b001))) | ((ird[8:6] == 3'b000) & !xStaticMem);
			lineOnehot[1]: Irdecod[32] = 1'b1;
			lineOnehot[4]: Irdecod[32] = (ird[7:6] == 2'b00) | Irdecod[40];
			lineOnehot[5]: Irdecod[32] = (ird[7:6] == 2'b00) | xIsScc;
			lineOnehot[8], lineOnehot[9], lineOnehot['hb], lineOnehot['hc], lineOnehot['hd], lineOnehot['he]: Irdecod[32] = ird[7:6] == 2'b00;
			default: Irdecod[32] = 1'b0;
		endcase
	end
	wire [1:1] sv2v_tmp_4419B;
	assign sv2v_tmp_4419B = (lineOnehot[0] & ird[8]) & eaAreg;
	always @(*) Irdecod[31] = sv2v_tmp_4419B;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (1'b1)
			lineOnehot[6]: Irdecod[39] = ird[11:8] == 4'b0001;
			lineOnehot[4]: Irdecod[39] = (ird[11:8] == 4'b1110) | (ird[11:6] == 6'b100001);
			default: Irdecod[39] = 1'b0;
		endcase
	end
	wire [1:1] sv2v_tmp_03DA9;
	assign sv2v_tmp_03DA9 = (lineOnehot[4] & ((ird[11:0] == 12'he77) | (ird[11:6] == 6'b010011))) | (lineOnehot[0] & (ird[8:6] == 3'b000));
	always @(*) Irdecod[38] = sv2v_tmp_03DA9;
	reg [15:0] ftuConst;
	wire [3:0] zero28 = (ird[11:9] == 0 ? 4'h8 : {1'b0, ird[11:9]});
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (1'b1)
			lineOnehot[6], lineOnehot[7]: ftuConst = {{8 {ird[7]}}, ird[7:0]};
			lineOnehot['h5], lineOnehot['he]: ftuConst = {12'b000000000000, zero28};
			lineOnehot['h8], lineOnehot['hc]: ftuConst = 16'h000f;
			lineOnehot[4]: ftuConst = 16'h0080;
			default: ftuConst = 1'sb0;
		endcase
	end
	wire [16:1] sv2v_tmp_D48F4;
	assign sv2v_tmp_D48F4 = ftuConst;
	always @(*) Irdecod[22-:16] = sv2v_tmp_D48F4;
	always @(*) begin
		if (_sv2v_0)
			;
		if (lineOnehot[4])
			case (ird[6:5])
				2'b00, 2'b01: Irdecod[6-:6] = 6;
				2'b11: Irdecod[6-:6] = 7;
				2'b10: Irdecod[6-:6] = {2'b10, ird[3:0]};
			endcase
		else
			Irdecod[6-:6] = 5;
	end
	wire eaAdir = ird[5:3] == 3'b001;
	wire size11 = ird[7] & ird[6];
	wire [1:1] sv2v_tmp_04E16;
	assign sv2v_tmp_04E16 = (((lineOnehot[9] | lineOnehot['hd]) & size11) | (lineOnehot[5] & eaAdir)) | ((lineOnehot[2] | lineOnehot[3]) & (ird[8:6] == 3'b001));
	always @(*) Irdecod[0] = sv2v_tmp_04E16;
	initial _sv2v_0 = 0;
endmodule
module excUnit (
	Clks,
	enT1,
	enT2,
	enT3,
	enT4,
	Nanod,
	Irdecod,
	Ird,
	pswS,
	ftu,
	iEdb,
	ccr,
	alue,
	prenEmpty,
	au05z,
	dcr4,
	ze,
	aob0,
	AblOut,
	Irc,
	oEdb,
	eab
);
	reg _sv2v_0;
	input wire [4:0] Clks;
	input enT1;
	input enT2;
	input enT3;
	input enT4;
	input wire [104:0] Nanod;
	input wire [41:0] Irdecod;
	input [15:0] Ird;
	input pswS;
	input [15:0] ftu;
	input [15:0] iEdb;
	output wire [7:0] ccr;
	output wire [15:0] alue;
	output wire prenEmpty;
	output wire au05z;
	output reg dcr4;
	output wire ze;
	output wire aob0;
	output wire [15:0] AblOut;
	output wire [15:0] Irc;
	output wire [15:0] oEdb;
	output wire [23:1] eab;
	localparam REG_USP = 15;
	localparam REG_SSP = 16;
	localparam REG_DT = 17;
	reg [15:0] regs68L [0:17];
	reg [15:0] regs68H [0:17];
	initial begin : sv2v_autoblock_1
		reg signed [31:0] i;
		for (i = 0; i < 18; i = i + 1)
			begin
				regs68L[i] <= 1'sb0;
				regs68H[i] <= 1'sb0;
			end
	end
	wire [31:0] SSP = {regs68H[REG_SSP], regs68L[REG_SSP]};
	wire [15:0] aluOut;
	wire [15:0] dbin;
	reg [15:0] dcrOutput;
	reg [15:0] PcL;
	reg [15:0] PcH;
	reg [31:0] auReg;
	reg [31:0] aob;
	reg [15:0] Ath;
	reg [15:0] Atl;
	reg [15:0] Dbl;
	reg [15:0] Dbh;
	reg [15:0] Abh;
	reg [15:0] Abl;
	reg [15:0] Abd;
	reg [15:0] Dbd;
	assign AblOut = Abl;
	assign au05z = ~|auReg[5:0];
	reg [15:0] dblMux;
	reg [15:0] dbhMux;
	reg [15:0] abhMux;
	reg [15:0] ablMux;
	reg [15:0] abdMux;
	reg [15:0] dbdMux;
	reg abdIsByte;
	reg Pcl2Dbl;
	reg Pch2Dbh;
	reg Pcl2Abl;
	reg Pch2Abh;
	reg [4:0] actualRx;
	reg [4:0] actualRy;
	reg [3:0] movemRx;
	reg byteNotSpAlign;
	reg [4:0] rxMux;
	reg [4:0] ryMux;
	reg [3:0] rxReg;
	reg [3:0] ryReg;
	reg rxIsSp;
	reg ryIsSp;
	reg rxIsAreg;
	reg ryIsAreg;
	always @(*) begin
		if (_sv2v_0)
			;
		if (Nanod[50]) begin
			rxMux = REG_SSP;
			rxIsSp = 1'b1;
			rxReg = 1'bx;
		end
		else if (Irdecod[35]) begin
			rxMux = REG_USP;
			rxIsSp = 1'b1;
			rxReg = 1'bx;
		end
		else if (Irdecod[37] & !Irdecod[39]) begin
			rxMux = REG_DT;
			rxIsSp = 1'b0;
			rxReg = 1'bx;
		end
		else begin
			if (Irdecod[39])
				rxReg = 15;
			else if (Irdecod[34])
				rxReg = movemRx;
			else
				rxReg = {Irdecod[24], Irdecod[30-:3]};
			if (&rxReg) begin
				rxMux = (pswS ? REG_SSP : 15);
				rxIsSp = 1'b1;
			end
			else begin
				rxMux = {1'b0, rxReg};
				rxIsSp = 1'b0;
			end
		end
		if (Irdecod[36] & !Nanod[29]) begin
			ryMux = REG_DT;
			ryIsSp = 1'b0;
			ryReg = 1'sbx;
		end
		else begin
			ryReg = (Nanod[29] ? Irc[15:12] : {Irdecod[23], Irdecod[27-:3]});
			ryIsSp = &ryReg;
			if (ryIsSp & pswS)
				ryMux = REG_SSP;
			else
				ryMux = {1'b0, ryReg};
		end
	end
	always @(posedge Clks[4]) begin
		if (enT4) begin
			byteNotSpAlign <= Irdecod[32] & ~(Nanod[28] ? rxIsSp : ryIsSp);
			actualRx <= rxMux;
			actualRy <= ryMux;
			rxIsAreg <= rxIsSp | rxMux[3];
			ryIsAreg <= ryIsSp | ryMux[3];
		end
		if (enT4)
			abdIsByte <= Nanod[0] & Irdecod[32];
	end
	wire ryl2Abl = Nanod[34] & (ryIsAreg | Nanod[4]);
	wire ryl2Abd = Nanod[34] & (~ryIsAreg | Nanod[4]);
	wire ryl2Dbl = Nanod[35] & (ryIsAreg | Nanod[2]);
	wire ryl2Dbd = Nanod[35] & (~ryIsAreg | Nanod[2]);
	wire rxl2Abl = Nanod[40] & (rxIsAreg | Nanod[4]);
	wire rxl2Abd = Nanod[40] & (~rxIsAreg | Nanod[4]);
	wire rxl2Dbl = Nanod[41] & (rxIsAreg | Nanod[2]);
	wire rxl2Dbd = Nanod[41] & (~rxIsAreg | Nanod[2]);
	reg abhIdle;
	reg ablIdle;
	reg abdIdle;
	reg dbhIdle;
	reg dblIdle;
	reg dbdIdle;
	always @(*) begin
		if (_sv2v_0)
			;
		{abhIdle, ablIdle, abdIdle} = 1'sb0;
		{dbhIdle, dblIdle, dbdIdle} = 1'sb0;
		(* full_case, parallel_case *)
		case (1'b1)
			ryl2Dbd: dbdMux = regs68L[actualRy];
			rxl2Dbd: dbdMux = regs68L[actualRx];
			Nanod[16]: dbdMux = alue;
			Nanod[7]: dbdMux = dbin;
			Nanod[13]: dbdMux = aluOut;
			Nanod[18]: dbdMux = dcrOutput;
			default: begin
				dbdMux = 1'sbx;
				dbdIdle = 1'b1;
			end
		endcase
		(* full_case, parallel_case *)
		case (1'b1)
			rxl2Dbl: dblMux = regs68L[actualRx];
			ryl2Dbl: dblMux = regs68L[actualRy];
			Nanod[93]: dblMux = ftu;
			Nanod[11]: dblMux = auReg[15:0];
			Nanod[70]: dblMux = Atl;
			Pcl2Dbl: dblMux = PcL;
			default: begin
				dblMux = 1'sbx;
				dblIdle = 1'b1;
			end
		endcase
		(* full_case, parallel_case *)
		case (1'b1)
			Nanod[45]: dbhMux = regs68H[actualRx];
			Nanod[33]: dbhMux = regs68H[actualRy];
			Nanod[11]: dbhMux = auReg[31:16];
			Nanod[67]: dbhMux = Ath;
			Pch2Dbh: dbhMux = PcH;
			default: begin
				dbhMux = 1'sbx;
				dbhIdle = 1'b1;
			end
		endcase
		(* full_case, parallel_case *)
		case (1'b1)
			ryl2Abd: abdMux = regs68L[actualRy];
			rxl2Abd: abdMux = regs68L[actualRx];
			Nanod[8]: abdMux = dbin;
			Nanod[12]: abdMux = aluOut;
			default: begin
				abdMux = 1'sbx;
				abdIdle = 1'b1;
			end
		endcase
		(* full_case, parallel_case *)
		case (1'b1)
			Pcl2Abl: ablMux = PcL;
			rxl2Abl: ablMux = regs68L[actualRx];
			ryl2Abl: ablMux = regs68L[actualRy];
			Nanod[92]: ablMux = ftu;
			Nanod[10]: ablMux = auReg[15:0];
			Nanod[62]: ablMux = aob[15:0];
			Nanod[71]: ablMux = Atl;
			default: begin
				ablMux = 1'sbx;
				ablIdle = 1'b1;
			end
		endcase
		(* full_case, parallel_case *)
		case (1'b1)
			Pch2Abh: abhMux = PcH;
			Nanod[44]: abhMux = regs68H[actualRx];
			Nanod[32]: abhMux = regs68H[actualRy];
			Nanod[10]: abhMux = auReg[31:16];
			Nanod[62]: abhMux = aob[31:16];
			Nanod[66]: abhMux = Ath;
			default: begin
				abhMux = 1'sbx;
				abhIdle = 1'b1;
			end
		endcase
	end
	reg [15:0] preAbh;
	reg [15:0] preAbl;
	reg [15:0] preAbd;
	reg [15:0] preDbh;
	reg [15:0] preDbl;
	reg [15:0] preDbd;
	always @(posedge Clks[4]) begin
		if (enT1) begin
			{preAbh, preAbl, preAbd} <= {abhMux, ablMux, abdMux};
			{preDbh, preDbl, preDbd} <= {dbhMux, dblMux, dbdMux};
		end
		if (enT2) begin
			if (Nanod[5])
				Abh <= {16 {(ablIdle ? preAbd[15] : preAbl[15])}};
			else if (abhIdle)
				Abh <= (ablIdle ? preAbd : preAbl);
			else
				Abh <= preAbh;
			if (~ablIdle)
				Abl <= preAbl;
			else
				Abl <= (Nanod[3] ? preAbh : preAbd);
			Abd <= (~abdIdle ? preAbd : (ablIdle ? preAbh : preAbl));
			if (Nanod[6])
				Dbh <= {16 {(dblIdle ? preDbd[15] : preDbl[15])}};
			else if (dbhIdle)
				Dbh <= (dblIdle ? preDbd : preDbl);
			else
				Dbh <= preDbh;
			if (~dblIdle)
				Dbl <= preDbl;
			else
				Dbl <= (Nanod[1] ? preDbh : preDbd);
			Dbd <= (~dbdIdle ? preDbd : (dblIdle ? preDbh : preDbl));
		end
	end
	wire au2Aob = Nanod[63] | (Nanod[11] & Nanod[65]);
	always @(posedge Clks[4])
		if (enT1 & au2Aob)
			aob <= auReg;
		else if (enT2) begin
			if (Nanod[65])
				aob <= {preDbh, (~dblIdle ? preDbl : preDbd)};
			else if (Nanod[64])
				aob <= {preAbh, (~ablIdle ? preAbl : preAbd)};
		end
	assign eab = aob[23:1];
	assign aob0 = aob[0];
	reg [31:0] auInpMux;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (Nanod[78-:3])
			3'b000: auInpMux = 0;
			3'b001: auInpMux = (byteNotSpAlign | Nanod[79] ? 1 : 2);
			3'b010: auInpMux = -4;
			3'b011: auInpMux = {Abh, Abl};
			3'b100: auInpMux = 2;
			3'b101: auInpMux = 4;
			3'b110: auInpMux = -2;
			3'b111: auInpMux = (byteNotSpAlign | Nanod[79] ? -1 : -2);
			default: auInpMux = 1'sbx;
		endcase
	end
	wire [16:0] aulow = Dbl + auInpMux[15:0];
	wire [31:0] auResult = {(Dbh + auInpMux[31:16]) + aulow[16], aulow[15:0]};
	always @(posedge Clks[4])
		if (Clks[2])
			auReg <= 1'sb0;
		else if (enT3 & Nanod[80])
			auReg <= auResult;
	always @(posedge Clks[4])
		if (enT3) begin
			if (Nanod[43] | Nanod[39]) begin
				if (~rxIsAreg) begin
					if (Nanod[43])
						regs68L[actualRx] <= Dbd;
					else if (abdIsByte)
						regs68L[actualRx][7:0] <= Abd[7:0];
					else
						regs68L[actualRx] <= Abd;
				end
				else
					regs68L[actualRx] <= (Nanod[43] ? Dbl : Abl);
			end
			if (Nanod[31] | Nanod[30]) begin
				if (~ryIsAreg) begin
					if (Nanod[31])
						regs68L[actualRy] <= Dbd;
					else if (abdIsByte)
						regs68L[actualRy][7:0] <= Abd[7:0];
					else
						regs68L[actualRy] <= Abd;
				end
				else
					regs68L[actualRy] <= (Nanod[31] ? Dbl : Abl);
			end
			if (Nanod[42] | Nanod[38])
				regs68H[actualRx] <= (Nanod[42] ? Dbh : Abh);
			if (Nanod[37] | Nanod[36])
				regs68H[actualRy] <= (Nanod[37] ? Dbh : Abh);
		end
	reg dbl2Pcl;
	reg dbh2Pch;
	reg abh2Pch;
	reg abl2Pcl;
	always @(posedge Clks[4]) begin
		if (Clks[3]) begin
			{dbl2Pcl, dbh2Pch, abh2Pch, abl2Pcl} <= 1'sb0;
			Pcl2Dbl <= 1'b0;
			Pch2Dbh <= 1'b0;
			Pcl2Abl <= 1'b0;
			Pch2Abh <= 1'b0;
		end
		else if (enT4) begin
			dbl2Pcl <= Nanod[53] & Nanod[48];
			dbh2Pch <= Nanod[54] & Nanod[49];
			abh2Pch <= Nanod[58] & Nanod[46];
			abl2Pcl <= Nanod[57] & Nanod[47];
			Pcl2Dbl <= Nanod[52] & Nanod[48];
			Pch2Dbh <= Nanod[51] & Nanod[49];
			Pcl2Abl <= Nanod[56] & Nanod[47];
			Pch2Abh <= Nanod[55] & Nanod[46];
		end
		if (enT1 & Nanod[9])
			PcL <= auReg[15:0];
		else if (enT3) begin
			if (dbl2Pcl)
				PcL <= Dbl;
			else if (abl2Pcl)
				PcL <= Abl;
		end
		if (enT1 & Nanod[9])
			PcH <= auReg[31:16];
		else if (enT3) begin
			if (dbh2Pch)
				PcH <= Dbh;
			else if (abh2Pch)
				PcH <= Abh;
		end
		if (enT3) begin
			if (Nanod[73])
				Atl <= Dbl;
			else if (Nanod[72])
				Atl <= Abl;
		end
		if (enT3) begin
			if (Nanod[69])
				Ath <= Abh;
			else if (Nanod[68])
				Ath <= Dbh;
		end
	end
	wire rmIdle;
	wire [3:0] prHbit;
	reg [15:0] prenLatch;
	assign prenEmpty = ~|prenLatch;
	pren rmPren(
		.mask(prenLatch),
		.hbit(prHbit)
	);
	always @(posedge Clks[4])
		if (enT1 & Nanod[91])
			prenLatch <= dbin;
		else if (enT3 & Nanod[90]) begin
			prenLatch[prHbit] <= 1'b0;
			movemRx <= (Irdecod[33] ? ~prHbit : prHbit);
		end
	wire [15:0] dcrCode;
	wire [3:0] dcrInput = (abdIsByte ? {1'b0, Abd[2:0]} : Abd[3:0]);
	onehotEncoder4 dcrDecoder(
		.bin(dcrInput),
		.bitMap(dcrCode)
	);
	always @(posedge Clks[4])
		if (Clks[2])
			dcr4 <= 1'sb0;
		else if (enT3 & Nanod[19]) begin
			dcrOutput <= dcrCode;
			dcr4 <= Abd[4];
		end
	reg [15:0] alub;
	always @(posedge Clks[4])
		if (enT3) begin
			if (Nanod[15])
				alub <= Dbd;
			else if (Nanod[14])
				alub <= Abd;
		end
	wire alueClkEn = enT3 & Nanod[17];
	reg [15:0] dobInput;
	wire dobIdle = ~|Nanod[60-:2];
	localparam NANO_DOB_ADB = 2'b10;
	localparam NANO_DOB_ALU = 2'b11;
	localparam NANO_DOB_DBD = 2'b01;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (Nanod[60-:2])
			NANO_DOB_ADB: dobInput = Abd;
			NANO_DOB_DBD: dobInput = Dbd;
			NANO_DOB_ALU: dobInput = aluOut;
			default: dobInput = 1'sbx;
		endcase
	end
	dataIo dataIo(
		.Clks(Clks),
		.enT1(enT1),
		.enT2(enT2),
		.enT3(enT3),
		.enT4(enT4),
		.Nanod(Nanod),
		.Irdecod(Irdecod),
		.iEdb(iEdb),
		.dobIdle(dobIdle),
		.dobInput(dobInput),
		.aob0(aob0),
		.Irc(Irc),
		.dbin(dbin),
		.oEdb(oEdb)
	);
	fx68kAlu alu(
		.clk(Clks[4]),
		.pwrUp(Clks[2]),
		.enT1(enT1),
		.enT3(enT3),
		.enT4(enT4),
		.ird(Ird),
		.aluColumn(Nanod[27-:3]),
		.aluAddrCtrl(Nanod[22]),
		.init(Nanod[21]),
		.finish(Nanod[20]),
		.aluIsByte(Irdecod[32]),
		.ftu2Ccr(Nanod[86]),
		.alub(alub),
		.ftu(ftu),
		.alueClkEn(alueClkEn),
		.alue(alue),
		.aluDataCtrl(Nanod[24-:2]),
		.iDataBus(Dbd),
		.iAddrBus(Abd),
		.ze(ze),
		.aluOut(aluOut),
		.ccr(ccr)
	);
	initial _sv2v_0 = 0;
endmodule
module dataIo (
	Clks,
	enT1,
	enT2,
	enT3,
	enT4,
	Nanod,
	Irdecod,
	iEdb,
	aob0,
	dobIdle,
	dobInput,
	Irc,
	dbin,
	oEdb
);
	input wire [4:0] Clks;
	input enT1;
	input enT2;
	input enT3;
	input enT4;
	input wire [104:0] Nanod;
	input wire [41:0] Irdecod;
	input [15:0] iEdb;
	input aob0;
	input dobIdle;
	input [15:0] dobInput;
	output reg [15:0] Irc;
	output reg [15:0] dbin;
	output wire [15:0] oEdb;
	reg [15:0] dob;
	reg xToDbin;
	reg xToIrc;
	reg dbinNoLow;
	reg dbinNoHigh;
	reg byteMux;
	reg isByte_T4;
	always @(posedge Clks[4]) begin
		if (enT4)
			isByte_T4 <= Irdecod[32];
		if (enT3) begin
			dbinNoHigh <= Nanod[98];
			dbinNoLow <= Nanod[99];
			byteMux <= (Nanod[101] & isByte_T4) & ~aob0;
		end
		if (enT1) begin
			xToDbin <= 1'b0;
			xToIrc <= 1'b0;
		end
		else if (enT3) begin
			xToDbin <= Nanod[75];
			xToIrc <= Nanod[74];
		end
		if (xToIrc & Clks[0])
			Irc <= iEdb;
		if (xToDbin & Clks[0]) begin
			if (~dbinNoLow)
				dbin[7:0] <= (byteMux ? iEdb[15:8] : iEdb[7:0]);
			if (~dbinNoHigh)
				dbin[15:8] <= (~byteMux & dbinNoLow ? iEdb[7:0] : iEdb[15:8]);
		end
	end
	reg byteCycle;
	always @(posedge Clks[4]) begin
		if (enT4)
			byteCycle <= Nanod[101] & Irdecod[32];
		if (enT3 & ~dobIdle) begin
			dob[7:0] <= (Nanod[99] ? dobInput[15:8] : dobInput[7:0]);
			dob[15:8] <= (byteCycle | Nanod[98] ? dobInput[7:0] : dobInput[15:8]);
		end
	end
	assign oEdb = dob;
endmodule
module uaddrDecode (
	opcode,
	a1,
	a2,
	a3,
	isPriv,
	isIllegal,
	isLineA,
	isLineF,
	lineBmap
);
	reg _sv2v_0;
	input [15:0] opcode;
	localparam UADDR_WIDTH = 10;
	output wire [9:0] a1;
	output wire [9:0] a2;
	output wire [9:0] a3;
	output reg isPriv;
	output wire isIllegal;
	output wire isLineA;
	output wire isLineF;
	output wire [15:0] lineBmap;
	wire [3:0] line = opcode[15:12];
	wire [3:0] eaCol;
	wire [3:0] movEa;
	onehotEncoder4 irLineDecod(
		.bin(line),
		.bitMap(lineBmap)
	);
	assign isLineA = lineBmap['ha];
	assign isLineF = lineBmap['hf];
	pla_lined pla_lined(
		.movEa(movEa),
		.col(eaCol),
		.opcode(opcode),
		.lineBmap(lineBmap),
		.palIll(isIllegal),
		.plaA1(a1),
		.plaA2(a2),
		.plaA3(a3)
	);
	function [3:0] eaDecode;
		input [5:0] eaBits;
		(* full_case, parallel_case *)
		case (eaBits[5:3])
			3'b111:
				case (eaBits[2:0])
					3'b000: eaDecode = 7;
					3'b001: eaDecode = 8;
					3'b010: eaDecode = 9;
					3'b011: eaDecode = 10;
					3'b100: eaDecode = 11;
					default: eaDecode = 12;
				endcase
			default: eaDecode = eaBits[5:3];
		endcase
	endfunction
	assign eaCol = eaDecode(opcode[5:0]);
	assign movEa = eaDecode({opcode[8:6], opcode[11:9]});
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (lineBmap)
			'h1: isPriv = (opcode & 16'hf5ff) == 16'h007c;
			'h10:
				if ((opcode & 16'hffc0) == 16'h46c0)
					isPriv = 1'b1;
				else if ((opcode & 16'hfff0) == 16'h4e60)
					isPriv = 1'b1;
				else if (((opcode == 16'h4e70) || (opcode == 16'h4e73)) || (opcode == 16'h4e72))
					isPriv = 1'b1;
				else
					isPriv = 1'b0;
			default: isPriv = 1'b0;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module onehotEncoder4 (
	bin,
	bitMap
);
	reg _sv2v_0;
	input [3:0] bin;
	output reg [15:0] bitMap;
	always @(*) begin
		if (_sv2v_0)
			;
		case (bin)
			'b0: bitMap = 16'h0001;
			'b1: bitMap = 16'h0002;
			'b10: bitMap = 16'h0004;
			'b11: bitMap = 16'h0008;
			'b100: bitMap = 16'h0010;
			'b101: bitMap = 16'h0020;
			'b110: bitMap = 16'h0040;
			'b111: bitMap = 16'h0080;
			'b1000: bitMap = 16'h0100;
			'b1001: bitMap = 16'h0200;
			'b1010: bitMap = 16'h0400;
			'b1011: bitMap = 16'h0800;
			'b1100: bitMap = 16'h1000;
			'b1101: bitMap = 16'h2000;
			'b1110: bitMap = 16'h4000;
			'b1111: bitMap = 16'h8000;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module pren (
	mask,
	hbit
);
	parameter size = 16;
	parameter outbits = 4;
	input [size - 1:0] mask;
	output reg [outbits - 1:0] hbit;
	always @(mask) begin : sv2v_autoblock_1
		integer i;
		hbit = 0;
		for (i = size - 1; i >= 0; i = i - 1)
			if (mask[i])
				hbit = i;
	end
endmodule
module sequencer (
	Clks,
	enT3,
	microLatch,
	A0Err,
	BerrA,
	busAddrErr,
	Spuria,
	Avia,
	Tpend,
	intPend,
	isIllegal,
	isPriv,
	excRst,
	isLineA,
	isLineF,
	psw,
	prenEmpty,
	au05z,
	dcr4,
	ze,
	i11,
	alue01,
	Ird,
	a1,
	a2,
	a3,
	tvn,
	nma
);
	reg _sv2v_0;
	input wire [4:0] Clks;
	input enT3;
	localparam UROM_WIDTH = 17;
	input [16:0] microLatch;
	input A0Err;
	input BerrA;
	input busAddrErr;
	input Spuria;
	input Avia;
	input Tpend;
	input intPend;
	input isIllegal;
	input isPriv;
	input excRst;
	input isLineA;
	input isLineF;
	input [15:0] psw;
	input prenEmpty;
	input au05z;
	input dcr4;
	input ze;
	input i11;
	input [1:0] alue01;
	input [15:0] Ird;
	localparam UADDR_WIDTH = 10;
	input [9:0] a1;
	input [9:0] a2;
	input [9:0] a3;
	output reg [3:0] tvn;
	output reg [9:0] nma;
	reg [9:0] uNma;
	reg [9:0] grp1Nma;
	reg [1:0] c0c1;
	reg a0Rst;
	wire A0Sel;
	wire inGrp0Exc;
	wire [9:0] dbNma = {microLatch[14:13], microLatch[6:5], microLatch[10:7], microLatch[12:11]};
	localparam BSER1_NMA = 'h3;
	localparam HALT1_NMA = 'h1;
	localparam RSTP0_NMA = 'h2;
	always @(*) begin
		if (_sv2v_0)
			;
		if (A0Err) begin
			if (a0Rst)
				nma = RSTP0_NMA;
			else if (inGrp0Exc)
				nma = HALT1_NMA;
			else
				nma = BSER1_NMA;
		end
		else
			nma = uNma;
	end
	always @(*) begin
		if (_sv2v_0)
			;
		if (microLatch[1])
			uNma = {microLatch[14:13], c0c1, microLatch[10:7], microLatch[12:11]};
		else
			case (microLatch[3:2])
				0: uNma = dbNma;
				1: uNma = (A0Sel ? grp1Nma : a1);
				2: uNma = a2;
				3: uNma = a3;
			endcase
	end
	wire [1:0] enl = {Ird[6], prenEmpty};
	wire [1:0] ms0 = {Ird[8], alue01[0]};
	wire [3:0] m01 = {au05z, Ird[8], alue01};
	localparam NF = 3;
	localparam ZF = 2;
	wire [1:0] nz1 = {psw[NF], psw[ZF]};
	localparam VF = 1;
	wire [1:0] nv = {psw[NF], psw[VF]};
	reg ccTest;
	wire [4:0] cbc = microLatch[6:2];
	localparam CF = 0;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (cbc)
			'h0: c0c1 = {i11, i11};
			'h1: c0c1 = (au05z ? 2'b01 : 2'b11);
			'h11: c0c1 = (au05z ? 2'b00 : 2'b11);
			'h2: c0c1 = {1'b0, ~psw[CF]};
			'h12: c0c1 = {1'b1, ~psw[CF]};
			'h3: c0c1 = {psw[ZF], psw[ZF]};
			'h4:
				case (nz1)
					'b0: c0c1 = 2'b10;
					'b10: c0c1 = 2'b01;
					'b1, 'b11: c0c1 = 2'b11;
				endcase
			'h5: c0c1 = {psw[NF], 1'b1};
			'h15: c0c1 = {1'b1, psw[NF]};
			'h6: c0c1 = {~nz1[1] & ~nz1[0], 1'b1};
			'h7:
				case (ms0)
					'b10, 'b0: c0c1 = 2'b11;
					'b1: c0c1 = 2'b01;
					'b11: c0c1 = 2'b10;
				endcase
			'h8:
				case (m01)
					'b0, 'b1, 'b100, 'b111: c0c1 = 2'b11;
					'b10, 'b11, 'b101: c0c1 = 2'b01;
					'b110: c0c1 = 2'b10;
					default: c0c1 = 2'b00;
				endcase
			'h9: c0c1 = (ccTest ? 2'b11 : 2'b01);
			'h19: c0c1 = (ccTest ? 2'b11 : 2'b10);
			'hc: c0c1 = (dcr4 ? 2'b01 : 2'b11);
			'h1c: c0c1 = (dcr4 ? 2'b10 : 2'b11);
			'ha: c0c1 = (ze ? 2'b11 : 2'b00);
			'hb: c0c1 = (nv == 2'b00 ? 2'b00 : 2'b11);
			'hd: c0c1 = {~psw[VF], ~psw[VF]};
			'he, 'h1e:
				case (enl)
					2'b00: c0c1 = 'b10;
					2'b10: c0c1 = 'b11;
					2'b01, 2'b11: c0c1 = {1'b0, microLatch[6]};
				endcase
			default: c0c1 = 1'sbx;
		endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (Ird[11:8])
			'h0: ccTest = 1'b1;
			'h1: ccTest = 1'b0;
			'h2: ccTest = ~psw[CF] & ~psw[ZF];
			'h3: ccTest = psw[CF] | psw[ZF];
			'h4: ccTest = ~psw[CF];
			'h5: ccTest = psw[CF];
			'h6: ccTest = ~psw[ZF];
			'h7: ccTest = psw[ZF];
			'h8: ccTest = ~psw[VF];
			'h9: ccTest = psw[VF];
			'ha: ccTest = ~psw[NF];
			'hb: ccTest = psw[NF];
			'hc: ccTest = (psw[NF] & psw[VF]) | (~psw[NF] & ~psw[VF]);
			'hd: ccTest = (psw[NF] & ~psw[VF]) | (~psw[NF] & psw[VF]);
			'he: ccTest = ((psw[NF] & psw[VF]) & ~psw[ZF]) | ((~psw[NF] & ~psw[VF]) & ~psw[ZF]);
			'hf: ccTest = (psw[ZF] | (psw[NF] & ~psw[VF])) | (~psw[NF] & psw[VF]);
		endcase
	end
	reg rTrace;
	reg rInterrupt;
	reg rIllegal;
	reg rPriv;
	reg rLineA;
	reg rLineF;
	reg rExcRst;
	reg rExcAdrErr;
	reg rExcBusErr;
	reg rSpurious;
	reg rAutovec;
	wire grp1LatchEn;
	wire grp0LatchEn;
	assign grp1LatchEn = microLatch[0] & (microLatch[1] | !microLatch[4]);
	assign grp0LatchEn = microLatch[4] & !microLatch[1];
	assign inGrp0Exc = (rExcRst | rExcBusErr) | rExcAdrErr;
	localparam SF = 13;
	always @(posedge Clks[4]) begin
		if (grp0LatchEn & enT3) begin
			rExcRst <= excRst;
			rExcBusErr <= BerrA;
			rExcAdrErr <= busAddrErr;
			rSpurious <= Spuria;
			rAutovec <= Avia;
		end
		if (grp1LatchEn & enT3) begin
			rTrace <= Tpend;
			rInterrupt <= intPend;
			rIllegal <= (isIllegal & ~isLineA) & ~isLineF;
			rLineA <= isLineA;
			rLineF <= isLineF;
			rPriv <= isPriv & !psw[SF];
		end
	end
	localparam ITLX1_NMA = 'h1c4;
	localparam TRAC1_NMA = 'h1c0;
	localparam TVN_AUTOVEC = 13;
	localparam TVN_INTERRUPT = 15;
	localparam TVN_SPURIOUS = 12;
	always @(*) begin
		if (_sv2v_0)
			;
		grp1Nma = TRAC1_NMA;
		if (rExcRst)
			tvn = 1'sb0;
		else if (rExcBusErr | rExcAdrErr)
			tvn = {1'b1, rExcAdrErr};
		else if (rSpurious | rAutovec)
			tvn = (rSpurious ? TVN_SPURIOUS : TVN_AUTOVEC);
		else if (rTrace)
			tvn = 9;
		else if (rInterrupt) begin
			tvn = TVN_INTERRUPT;
			grp1Nma = ITLX1_NMA;
		end
		else
			(* full_case, parallel_case *)
			case (1'b1)
				rIllegal: tvn = 4;
				rPriv: tvn = 8;
				rLineA: tvn = 10;
				rLineF: tvn = 11;
				default: tvn = 1;
			endcase
	end
	assign A0Sel = ((((rIllegal | rLineF) | rLineA) | rPriv) | rTrace) | rInterrupt;
	always @(posedge Clks[4])
		if (Clks[3])
			a0Rst <= 1'b1;
		else if (enT3)
			a0Rst <= 1'b0;
	initial _sv2v_0 = 0;
endmodule
module busArbiter (
	Clks,
	BRi,
	BgackI,
	Halti,
	bgBlock,
	busAvail,
	BGn
);
	reg _sv2v_0;
	input wire [4:0] Clks;
	input BRi;
	input BgackI;
	input Halti;
	input bgBlock;
	output wire busAvail;
	output reg BGn;
	reg [31:0] dmaPhase;
	reg [31:0] next;
	always @(*) begin
		if (_sv2v_0)
			;
		case (dmaPhase)
			32'd0: next = 32'd1;
			32'd1:
				if (bgBlock)
					next = 32'd1;
				else if (~BgackI)
					next = 32'd4;
				else if (~BRi)
					next = 32'd2;
				else
					next = 32'd1;
			32'd4:
				if (~BRi & !bgBlock)
					next = 32'd6;
				else if (~BgackI & !bgBlock)
					next = 32'd4;
				else
					next = 32'd1;
			32'd2: next = 32'd3;
			32'd3: next = (~BRi & BgackI ? 32'd3 : 32'd4);
			32'd6: next = 32'd5;
			32'd5:
				case ({BgackI, BRi})
					2'b11: next = 32'd1;
					2'b10: next = 32'd3;
					2'b01: next = 32'd7;
					2'b00: next = 32'd5;
				endcase
			32'd7: next = 32'd4;
			default: next = 32'd1;
		endcase
	end
	reg granting;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (next)
			32'd2, 32'd6, 32'd3, 32'd5: granting = 1'b1;
			default: granting = 1'b0;
		endcase
	end
	reg rGranted;
	assign busAvail = ((Halti & BRi) & BgackI) & ~rGranted;
	always @(posedge Clks[4]) begin
		if (Clks[3]) begin
			dmaPhase <= 32'd0;
			rGranted <= 1'b0;
		end
		else if (Clks[0]) begin
			dmaPhase <= next;
			rGranted <= granting;
		end
		if (Clks[3])
			BGn <= 1'b1;
		else if (Clks[1])
			BGn <= ~rGranted;
	end
	initial _sv2v_0 = 0;
endmodule
module busControl (
	Clks,
	enT1,
	enT4,
	permStart,
	permStop,
	iStop,
	aob0,
	isWrite,
	isByte,
	isRmc,
	busAvail,
	bgBlock,
	busAddrErr,
	waitBusCycle,
	busStarting,
	addrOe,
	bciWrite,
	rDtack,
	BeDebounced,
	Vpai,
	ASn,
	LDSn,
	UDSn,
	eRWn
);
	reg _sv2v_0;
	input wire [4:0] Clks;
	input enT1;
	input enT4;
	input permStart;
	input permStop;
	input iStop;
	input aob0;
	input isWrite;
	input isByte;
	input isRmc;
	input busAvail;
	output wire bgBlock;
	output wire busAddrErr;
	output wire waitBusCycle;
	output wire busStarting;
	output reg addrOe;
	output wire bciWrite;
	input rDtack;
	input BeDebounced;
	input Vpai;
	output wire ASn;
	output wire LDSn;
	output wire UDSn;
	output wire eRWn;
	reg rAS;
	reg rLDS;
	reg rUDS;
	reg rRWn;
	assign ASn = rAS;
	assign LDSn = rLDS;
	assign UDSn = rUDS;
	assign eRWn = rRWn;
	reg dataOe;
	reg bcPend;
	reg isWriteReg;
	reg bciByte;
	reg isRmcReg;
	reg wendReg;
	assign bciWrite = isWriteReg;
	reg addrOeDelay;
	reg isByteT4;
	wire canStart;
	wire busEnd;
	wire bcComplete;
	wire bcReset;
	wire isRcmReset = (bcComplete & bcReset) & isRmcReg;
	assign busAddrErr = aob0 & ~bciByte;
	wire busRetry = ~busAddrErr & 1'b0;
	reg [31:0] busPhase;
	reg [31:0] next;
	always @(posedge Clks[4])
		if (Clks[3])
			busPhase <= 32'd0;
		else if (Clks[1])
			busPhase <= next;
	always @(*) begin
		if (_sv2v_0)
			;
		case (busPhase)
			32'd0: next = 32'd1;
			32'd6: next = 32'd1;
			32'd2: next = 32'd3;
			32'd3: next = 32'd4;
			32'd4: next = (busEnd ? 32'd5 : 32'd4);
			32'd5: next = (isRcmReset ? 32'd6 : (canStart ? 32'd2 : 32'd1));
			32'd1: next = (canStart ? 32'd2 : 32'd1);
			default: next = 32'd1;
		endcase
	end
	wire rmcIdle = ((busPhase == 32'd1) & ~ASn) & isRmcReg;
	assign canStart = (((busAvail | rmcIdle) & (bcPend | permStart)) & !busRetry) & !bcReset;
	wire busEnding = (next == 32'd1) | (next == 32'd2);
	assign busStarting = busPhase == 32'd2;
	assign busEnd = ~rDtack | iStop;
	assign bcComplete = busPhase == 32'd5;
	wire bciClear = bcComplete & ~busRetry;
	assign bcReset = Clks[3] | ((addrOeDelay & BeDebounced) & Vpai);
	assign waitBusCycle = wendReg & !bcComplete;
	assign bgBlock = ((busPhase == 32'd2) & ASn) | (busPhase == 32'd6);
	always @(posedge Clks[4]) begin
		if (Clks[3])
			addrOe <= 1'b0;
		else if (Clks[0] & (busPhase == 32'd2))
			addrOe <= 1'b1;
		else if (Clks[1] & (busPhase == 32'd6))
			addrOe <= 1'b0;
		else if ((Clks[1] & ~isRmcReg) & busEnding)
			addrOe <= 1'b0;
		if (Clks[1])
			addrOeDelay <= addrOe;
		if (Clks[3]) begin
			rAS <= 1'b1;
			rUDS <= 1'b1;
			rLDS <= 1'b1;
			rRWn <= 1'b1;
			dataOe <= 1'sb0;
		end
		else begin
			if ((Clks[0] & isWriteReg) & (busPhase == 32'd3))
				dataOe <= 1'b1;
			else if (Clks[1] & (busEnding | (busPhase == 32'd1)))
				dataOe <= 1'b0;
			if (Clks[1] & busEnding)
				rRWn <= 1'b1;
			else if (Clks[1] & isWriteReg) begin
				if ((busPhase == 32'd2) & isWriteReg)
					rRWn <= 1'b0;
			end
			if (Clks[1] & (busPhase == 32'd2))
				rAS <= 1'b0;
			else if (Clks[0] & (busPhase == 32'd6))
				rAS <= 1'b1;
			else if ((Clks[0] & bcComplete) & ~32'd6) begin
				if (~isRmcReg)
					rAS <= 1'b1;
			end
			if (Clks[1] & (busPhase == 32'd2)) begin
				if (~isWriteReg & !busAddrErr) begin
					rUDS <= ~(~bciByte | ~aob0);
					rLDS <= ~(~bciByte | aob0);
				end
			end
			else if (((Clks[1] & isWriteReg) & (busPhase == 32'd3)) & !busAddrErr) begin
				rUDS <= ~(~bciByte | ~aob0);
				rLDS <= ~(~bciByte | aob0);
			end
			else if (Clks[0] & bcComplete) begin
				rUDS <= 1'b1;
				rLDS <= 1'b1;
			end
		end
	end
	always @(posedge Clks[4])
		if (enT4)
			isByteT4 <= isByte;
	always @(posedge Clks[4])
		if (Clks[2]) begin
			bcPend <= 1'b0;
			wendReg <= 1'b0;
			isWriteReg <= 1'b0;
			bciByte <= 1'b0;
			isRmcReg <= 1'b0;
		end
		else if (Clks[0] & (bciClear | bcReset)) begin
			bcPend <= 1'b0;
			wendReg <= 1'b0;
		end
		else begin
			if (enT1 & permStart) begin
				isWriteReg <= isWrite;
				bciByte <= isByteT4;
				isRmcReg <= isRmc & ~isWrite;
				bcPend <= 1'b1;
			end
			if (enT1)
				wendReg <= permStop;
		end
	initial _sv2v_0 = 0;
endmodule
module uRom (
	clk,
	microAddr,
	microOutput
);
	input clk;
	localparam UADDR_WIDTH = 10;
	input [9:0] microAddr;
	localparam UROM_WIDTH = 17;
	output reg [16:0] microOutput;
	localparam UROM_DEPTH = 1024;
	reg [16:0] uRam [0:1023];
	initial $readmemb("microrom.mem", uRam);
	always @(posedge clk) microOutput <= uRam[microAddr];
endmodule
module nanoRom (
	clk,
	nanoAddr,
	nanoOutput
);
	input clk;
	localparam NADDR_WIDTH = 9;
	input [8:0] nanoAddr;
	localparam NANO_WIDTH = 68;
	output reg [67:0] nanoOutput;
	localparam NANO_DEPTH = 336;
	reg [67:0] nRam [0:335];
	initial $readmemb("nanorom.mem", nRam);
	always @(posedge clk) nanoOutput <= nRam[nanoAddr];
endmodule
module microToNanoAddr (
	uAddr,
	orgAddr
);
	localparam UADDR_WIDTH = 10;
	input [9:0] uAddr;
	localparam NADDR_WIDTH = 9;
	output wire [8:0] orgAddr;
	wire [9:2] baseAddr = uAddr[9:2];
	reg [8:2] orgBase;
	assign orgAddr = {orgBase, uAddr[1:0]};
	always @(baseAddr)
		case (baseAddr)
			'h0: orgBase = 7'h00;
			'h1: orgBase = 7'h01;
			'h2: orgBase = 7'h02;
			'h3: orgBase = 7'h02;
			'h8: orgBase = 7'h03;
			'h9: orgBase = 7'h04;
			'ha: orgBase = 7'h05;
			'hb: orgBase = 7'h05;
			'h10: orgBase = 7'h06;
			'h11: orgBase = 7'h07;
			'h12: orgBase = 7'h08;
			'h13: orgBase = 7'h08;
			'h18: orgBase = 7'h09;
			'h19: orgBase = 7'h0a;
			'h1a: orgBase = 7'h0b;
			'h1b: orgBase = 7'h0b;
			'h20: orgBase = 7'h0c;
			'h21: orgBase = 7'h0d;
			'h22: orgBase = 7'h0e;
			'h23: orgBase = 7'h0d;
			'h28: orgBase = 7'h0f;
			'h29: orgBase = 7'h10;
			'h2a: orgBase = 7'h11;
			'h2b: orgBase = 7'h10;
			'h30: orgBase = 7'h12;
			'h31: orgBase = 7'h13;
			'h32: orgBase = 7'h14;
			'h33: orgBase = 7'h14;
			'h38: orgBase = 7'h15;
			'h39: orgBase = 7'h16;
			'h3a: orgBase = 7'h17;
			'h3b: orgBase = 7'h17;
			'h40: orgBase = 7'h18;
			'h41: orgBase = 7'h18;
			'h42: orgBase = 7'h18;
			'h43: orgBase = 7'h18;
			'h44: orgBase = 7'h19;
			'h45: orgBase = 7'h19;
			'h46: orgBase = 7'h19;
			'h47: orgBase = 7'h19;
			'h48: orgBase = 7'h1a;
			'h49: orgBase = 7'h1a;
			'h4a: orgBase = 7'h1a;
			'h4b: orgBase = 7'h1a;
			'h4c: orgBase = 7'h1b;
			'h4d: orgBase = 7'h1b;
			'h4e: orgBase = 7'h1b;
			'h4f: orgBase = 7'h1b;
			'h54: orgBase = 7'h1c;
			'h55: orgBase = 7'h1d;
			'h56: orgBase = 7'h1e;
			'h57: orgBase = 7'h1f;
			'h5c: orgBase = 7'h20;
			'h5d: orgBase = 7'h21;
			'h5e: orgBase = 7'h22;
			'h5f: orgBase = 7'h23;
			'h70: orgBase = 7'h24;
			'h71: orgBase = 7'h24;
			'h72: orgBase = 7'h24;
			'h73: orgBase = 7'h24;
			'h74: orgBase = 7'h24;
			'h75: orgBase = 7'h24;
			'h76: orgBase = 7'h24;
			'h77: orgBase = 7'h24;
			'h78: orgBase = 7'h25;
			'h79: orgBase = 7'h25;
			'h7a: orgBase = 7'h25;
			'h7b: orgBase = 7'h25;
			'h7c: orgBase = 7'h25;
			'h7d: orgBase = 7'h25;
			'h7e: orgBase = 7'h25;
			'h7f: orgBase = 7'h25;
			'h84: orgBase = 7'h26;
			'h85: orgBase = 7'h27;
			'h86: orgBase = 7'h28;
			'h87: orgBase = 7'h29;
			'h8c: orgBase = 7'h2a;
			'h8d: orgBase = 7'h2b;
			'h8e: orgBase = 7'h2c;
			'h8f: orgBase = 7'h2d;
			'h94: orgBase = 7'h2e;
			'h95: orgBase = 7'h2f;
			'h96: orgBase = 7'h30;
			'h97: orgBase = 7'h31;
			'h9c: orgBase = 7'h32;
			'h9d: orgBase = 7'h33;
			'h9e: orgBase = 7'h34;
			'h9f: orgBase = 7'h35;
			'ha4: orgBase = 7'h36;
			'ha5: orgBase = 7'h36;
			'ha6: orgBase = 7'h37;
			'ha7: orgBase = 7'h37;
			'hac: orgBase = 7'h38;
			'had: orgBase = 7'h38;
			'hae: orgBase = 7'h39;
			'haf: orgBase = 7'h39;
			'hb4: orgBase = 7'h3a;
			'hb5: orgBase = 7'h3a;
			'hb6: orgBase = 7'h3b;
			'hb7: orgBase = 7'h3b;
			'hbc: orgBase = 7'h3c;
			'hbd: orgBase = 7'h3c;
			'hbe: orgBase = 7'h3d;
			'hbf: orgBase = 7'h3d;
			'hc0: orgBase = 7'h3e;
			'hc1: orgBase = 7'h3f;
			'hc2: orgBase = 7'h40;
			'hc3: orgBase = 7'h41;
			'hc8: orgBase = 7'h42;
			'hc9: orgBase = 7'h43;
			'hca: orgBase = 7'h44;
			'hcb: orgBase = 7'h45;
			'hd0: orgBase = 7'h46;
			'hd1: orgBase = 7'h47;
			'hd2: orgBase = 7'h48;
			'hd3: orgBase = 7'h49;
			'hd8: orgBase = 7'h4a;
			'hd9: orgBase = 7'h4b;
			'hda: orgBase = 7'h4c;
			'hdb: orgBase = 7'h4d;
			'he0: orgBase = 7'h4e;
			'he1: orgBase = 7'h4e;
			'he2: orgBase = 7'h4f;
			'he3: orgBase = 7'h4f;
			'he8: orgBase = 7'h50;
			'he9: orgBase = 7'h50;
			'hea: orgBase = 7'h51;
			'heb: orgBase = 7'h51;
			'hf0: orgBase = 7'h52;
			'hf1: orgBase = 7'h52;
			'hf2: orgBase = 7'h52;
			'hf3: orgBase = 7'h52;
			'hf8: orgBase = 7'h53;
			'hf9: orgBase = 7'h53;
			'hfa: orgBase = 7'h53;
			'hfb: orgBase = 7'h53;
			default: orgBase = 1'sbx;
		endcase
endmodule
