#import "XtensaCtx.h"
#import "XtensaCPU.h"
#import <Hopper/CommonTypes.h>
#import <Hopper/CPUDefinition.h>
#import <Hopper/HPDisassembledFile.h>

@implementation XtensaCtx {
	XtensaCPU *_cpu;
	NSObject<HPDisassembledFile> *_file;
}

- (instancetype)initWithCPU:(XtensaCPU *)cpu andFile:(NSObject<HPDisassembledFile> *)file {
	if (self = [super init]) {
		_cpu = cpu;
		_file = file;
	}
	return self;
}

- (void)dealloc {
}

- (NSObject<CPUDefinition> *)cpuDefinition {
	return _cpu;
}

- (void)initDisasmStructure:(DisasmStruct *)disasm withSyntaxIndex:(NSUInteger)syntaxIndex {
	bzero(disasm, sizeof(DisasmStruct));
}

// Analysis

- (Address)adjustCodeAddress:(Address)address {
	return address;
}

- (uint8_t)cpuModeFromAddress:(Address)address {
	return 0;
}

- (BOOL)addressForcesACPUMode:(Address)address {
	return NO;
}

- (Address)nextAddressToTryIfInstructionFailedToDecodeAt:(Address)address forCPUMode:(uint8_t)mode {
	return address+1;
}

- (int)isNopAt:(Address)address {
	uint32_t word = [self readWordAt:address];
	if((word & 0xffff) == 0xf03d) 
		return 2;
	if(word == 0x0020f0)
		return 3;
	return 0;
}

- (BOOL)hasProcedurePrologAt:(Address)address {
	// procedures usually begins with a "addi a1, a1 -X"
	uint32_t word = [self readWordAt:address];
	return (word & 0x00ffff) == 0xc112; // this is XXc112, not a 2-byte instruction
}

- (NSUInteger)detectedPaddingLengthAt:(Address)address {
	NSUInteger len = 0;
	while ([_file readUInt8AtVirtualAddress:address] == 0) {
		address += 1;
		len += 1;
	}

	return len;
}

- (void)analysisBeginsAt:(Address)entryPoint {

}

- (void)analysisEnded {

}

- (void)procedureAnalysisBeginsForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {

}

- (void)procedureAnalysisOfPrologForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {

}

- (void)procedureAnalysisOfEpilogForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {
	
}

- (void)procedureAnalysisEndedForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {

}

- (void)procedureAnalysisContinuesOnBasicBlock:(NSObject<HPBasicBlock> *)basicBlock {

}

- (Address)getThunkDestinationForInstructionAt:(Address)address {
	return BAD_ADDRESS;
}

- (void)resetDisassembler {

}

- (uint8_t)estimateCPUModeAtVirtualAddress:(Address)address {
	return 0;
}

- (uint32_t)readWordAt:(uint32_t)address {
	// for example 31 00 00 48
	// => 0x48000031
	// => 0x000031 = l32r a3, ....
	return [_file readUInt32AtVirtualAddress:address] & 0xffffff;
}

enum OperandType {
	Operand_NONE,
	Operand_REG,
	Operand_IMM,
	Operand_MEM_INDEX,
	Operand_RELU,

	Operand_RELA,
	Operand_RELAL,
	Operand_MEM,
};

typedef int64_t (*xlatefun_t)(int64_t);

struct Operand {
	enum OperandType type;
	int size, rshift, size2, rshift2;
	bool signext;
	int vshift, off;
	xlatefun_t xlate;
	int bitwidth; // default = 8
	int regbase[2];
};

struct Format {
	int length;
	struct Operand operands[4];
};

struct Instr {
	const char *mnemonic;
	uint32_t opcode, mask;
	const struct Format *format;
	DisasmBranchType branchType;
};

static int64_t b4const(int64_t val)
{
	static const int lut[] = { -1, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 32, 64, 128, 256 };
	return lut[val];
}

static int64_t b4constu(int64_t val)
{
	static const int lut[] = { 32768, 65536, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 32, 64, 128, 256};
	return lut[val];
}

static int64_t movi_n(int64_t val)
{
	return (val & 0x60) != 0x60 ? val :  -(0x20 - (val & 0x1f));
}

static int64_t addin(int64_t val)
{
	return val ? val : -1;
}

static int64_t shimm(int64_t val)
{
	return 32-val;
}

enum xtensa_specreg {
#define SPECIAL_REGISTER(a,b) Xtensa_Specreg_ ## a,
#include "Xtensa_specreg.h"
#undef SPECIAL_REGISTER
};
static int specreg_from_xtensa[256] = 
{
#define SPECIAL_REGISTER(a,b) [b] = Xtensa_Specreg_ ## a,
#include "Xtensa_specreg.h"
#undef SPECIAL_REGISTER
};
static int64_t specreg(int64_t val)
{
	return specreg_from_xtensa[(unsigned int)val & 0xff] | 0x1000;
}

struct  Format  fmt_NONE	= {3, {}};
struct  Format  fmt_NNONE	= {2, {}};
struct  Format  fmt_RRR		= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 8}, {Operand_REG, 4, 4}}};
struct  Format  fmt_RRR_extui	= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 4}, {Operand_IMM, 4, 8, 1, 16}, {Operand_IMM, 4, 20, .off=1}}};
struct  Format  fmt_RRR_1imm	= {3, {{Operand_IMM, 4, 8},}};
struct  Format  fmt_RRR_2imm	= {3, {{Operand_IMM, 4, 8}, {Operand_IMM, 4, 4}}};
struct  Format  fmt_RRR_immr	= {3, {{Operand_REG, 4, 4}, {Operand_IMM, 4, 8}}};
struct  Format  fmt_RRR_2r	= {3, {{Operand_REG, 4, 4}, {Operand_REG, 4, 8}}};
struct  Format  fmt_RRR_2rr	= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 4}}};
struct  Format  fmt_RRR_sll	= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 8}}};
struct  Format  fmt_RRR_slli	= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 8}, {Operand_IMM, 4, 4, 1, 20, .xlate=shimm}}};
struct  Format  fmt_RRR_srai	= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 4}, {Operand_IMM, 4, 8, 1, 20}}};
struct  Format  fmt_RRR_sh	= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 4}, {Operand_IMM, 4, 8}}};
struct  Format  fmt_RRR_ssa	= {3, {{Operand_REG, 4, 8},}};
struct  Format  fmt_RRR_ssai	= {3, {{Operand_IMM, 4, 8, 1, 4},}};
struct  Format  fmt_RRI8	= {3, {{Operand_REG, 4, 4}, {Operand_REG, 4, 8}, {Operand_IMM, 8, 16, .signext = true}}};
struct  Format  fmt_RRI8_addmi	= {3, {{Operand_REG, 4, 4}, {Operand_REG, 4, 8}, {Operand_IMM, 8, 16, .signext = true, .vshift=8, .bitwidth = 32}}};
struct  Format  fmt_RRI8_i12	= {3, {{Operand_REG, 4, 4}, {Operand_IMM, 8, 16, 4, 8, .bitwidth = 16 }}};
struct  Format  fmt_RRI8_disp	= {3, {{Operand_REG, 4, 4}, {Operand_MEM_INDEX, 8, 16, .vshift=0, .regbase={4, 8}}}};
struct  Format  fmt_RRI8_disp16	= {3, {{Operand_REG, 4, 4}, {Operand_MEM_INDEX, 8, 16, .vshift=1, .bitwidth = 16, .regbase={4, 8}}}};
struct  Format  fmt_RRI8_disp32	= {3, {{Operand_REG, 4, 4}, {Operand_MEM_INDEX, 8, 16, .vshift=2, .bitwidth = 32, .regbase={4, 8}}}};
struct  Format  fmt_RRI8_b	= {3, {{Operand_REG, 4, 8}, {Operand_REG, 4, 4}, {Operand_RELA, 8, 16}}};
struct  Format  fmt_RRI8_bb	= {3, {{Operand_REG, 4, 8}, {Operand_IMM, 4, 4, 1, 12}, {Operand_RELA, 8, 16}}};
struct  Format  fmt_RI16	= {3, {{Operand_REG, 4, 4}, {Operand_MEM, 16, 8, .bitwidth = 32 }}};
struct  Format  fmt_BRI8	= {3, {{Operand_REG, 4, 12}, {Operand_REG, 4, 8}, {Operand_RELA, 8, 16}}};
struct  Format  fmt_BRI8_imm	= {3, {{Operand_REG, 4, 8}, {Operand_IMM, 4, 12, .xlate = b4const}, {Operand_RELA, 8, 16}}};
struct  Format  fmt_BRI8_immu	= {3, {{Operand_REG, 4, 8}, {Operand_IMM, 4, 12, .xlate = b4constu}, {Operand_RELA, 8, 16}}};
struct  Format  fmt_BRI12	= {3, {{Operand_REG, 4, 8}, {Operand_RELA, 12, 12}}};
struct  Format  fmt_CALL	= {3, {{Operand_RELA, 18, 6},}};
struct  Format  fmt_CALL_sh	= {3, {{Operand_RELAL, 18, 6},}};
struct  Format  fmt_CALLX	= {3, {{Operand_REG, 4, 8},}};
struct  Format  fmt_RSR		= {3, {{Operand_REG, 8, 8, .xlate=specreg}, {Operand_REG, 4, 4}}};
struct  Format  fmt_RSR_spec	= {3, {{Operand_REG, 4, 4},}};
struct  Format  fmt_RRRN	= {2, {{Operand_REG, 4, 12}, {Operand_REG, 4, 8}, {Operand_REG, 4, 4}}};
struct  Format  fmt_RRRN_addi	= {2, {{Operand_REG, 4, 12}, {Operand_REG, 4, 8}, {Operand_IMM, 4, 4, .xlate=addin}}};
struct  Format  fmt_RRRN_2r	= {2, {{Operand_REG, 4, 4}, {Operand_REG, 4, 8}}};
struct  Format  fmt_RRRN_disp	= {2, {{Operand_REG, 4, 4}, {Operand_MEM_INDEX, 4, 12, .vshift=2, .regbase={4, 8}}}};
struct  Format  fmt_RI6		= {2, {{Operand_REG, 4, 8}, {Operand_RELU, 4, 12, 2, 4}}};
struct  Format  fmt_RI7		= {2, {{Operand_REG, 4, 8}, {Operand_IMM, 4, 12, 3, 4, .xlate=movi_n}}};

struct Instr opcodes[] = {
	{ "abs",    0x600100, 0xff0f0f, &fmt_RRR_2rr },
	{ "add",    0x800000, 0xff000f, &fmt_RRR },
	{ "addi",   0x00c002, 0x00f00f, &fmt_RRI8 },
	{ "addmi",  0x00d002, 0x00f00f, &fmt_RRI8_addmi },
	{ "addx2",  0x900000, 0xff000f, &fmt_RRR },
	{ "addx4",  0xa00000, 0xff000f, &fmt_RRR },
	{ "addx8",  0xb00000, 0xff000f, &fmt_RRR },
	{ "and",    0x100000, 0xff000f, &fmt_RRR },
	{ "ball",   0x004007, 0x00f00f, &fmt_RRI8_b }, // FIXME
	{ "bany",   0x008007, 0x00f00f, &fmt_RRI8_b }, // ...
	{ "bbc",    0x005007, 0x00f00f, &fmt_RRI8_b }, //
	{ "bbs",    0x00d007, 0x00f00f, &fmt_RRI8_b }, // 
	{ "bbci",   0x006007, 0x00e00f, &fmt_RRI8_bb }, //
	{ "bbsi",   0x00e007, 0x00e00f, &fmt_RRI8_bb }, // ..FIXME
	{ "beq",    0x001007, 0x00f00f, &fmt_RRI8_b, DISASM_BRANCH_JE },
	{ "beqi",   0x000026, 0x0000ff, &fmt_BRI8_imm, DISASM_BRANCH_JE }, // was RRI8
	{ "beqz",   0x000016, 0x0000ff, &fmt_BRI12, DISASM_BRANCH_JE },
	{ "bge",    0x00a007, 0x00f00f, &fmt_RRI8_b, DISASM_BRANCH_JGE },
	{ "bgei",   0x0000e6, 0x0000ff, &fmt_BRI8_imm, DISASM_BRANCH_JGE },
	{ "bgeu",   0x00b007, 0x00f00f, &fmt_RRI8_b, DISASM_BRANCH_JGE },
	{ "bgeui",  0x0000f6, 0x0000ff, &fmt_BRI8_immu, DISASM_BRANCH_JGE },
	{ "bgez",   0x0000d6, 0x0000ff, &fmt_BRI12, DISASM_BRANCH_JGE },
	{ "blt",    0x002007, 0x00f00f, &fmt_RRI8_b, DISASM_BRANCH_JL },
	{ "blti",   0x0000a6, 0x0000ff, &fmt_BRI8_imm, DISASM_BRANCH_JL },
	{ "bltu",   0x003007, 0x00f00f, &fmt_RRI8_b, DISASM_BRANCH_JL },
	{ "bltui",  0x0000b6, 0x0000ff, &fmt_BRI8_immu, DISASM_BRANCH_JL },
	{ "bltz",   0x000096, 0x0000ff, &fmt_BRI12, DISASM_BRANCH_JL },
	{ "bnall",  0x00c007, 0x00f00f, &fmt_RRI8_b }, // FIXME
	{ "bnone",  0x000007, 0x00f00f, &fmt_RRI8_b }, // FIXME
	{ "bne",    0x009007, 0x00f00f, &fmt_RRI8_b, DISASM_BRANCH_JNE },
	{ "bnei",   0x000066, 0x0000ff, &fmt_BRI8_imm, DISASM_BRANCH_JNE },
	{ "bnez",   0x000056, 0x0000ff, &fmt_BRI12, DISASM_BRANCH_JNE },
	{ "break",  0x004000, 0xfff00f, &fmt_RRR_2imm },
	{ "call0",  0x000005, 0x00003f, &fmt_CALL_sh, DISASM_BRANCH_CALL },
	{ "callx0", 0x0000c0, 0xfff0ff, &fmt_CALLX, DISASM_BRANCH_CALL },
	{ "dsync",  0x002030, 0xffffff, &fmt_NONE },
	{ "esync",  0x002020, 0xffffff, &fmt_NONE },
	{ "extui",  0x040000, 0x0e000f, &fmt_RRR_extui },
	{ "extw",   0x0020d0, 0xffffff, &fmt_NONE },
	{ "isync",  0x002000, 0xffffff, &fmt_NONE },
//		{ "ill",	   0x000000, 0xffffff, &fmt_NONE },	// normally one not need this
	{ "j",      0x000006, 0x00003f, &fmt_CALL, DISASM_BRANCH_JMP },
	{ "jx",     0x0000a0, 0xfff0ff, &fmt_CALLX, DISASM_BRANCH_JMP },
	{ "l8ui",   0x000002, 0x00f00f, &fmt_RRI8_disp },
	{ "l16si",  0x009002, 0x00f00f, &fmt_RRI8_disp16 },
	{ "l16ui",  0x001002, 0x00f00f, &fmt_RRI8_disp16 },
	{ "l32i",   0x002002, 0x00f00f, &fmt_RRI8_disp32 },
	{ "l32r",   0x000001, 0x00000f, &fmt_RI16 },
	{ "memw",   0x0020c0, 0xffffff, &fmt_NONE },
	{ "moveqz", 0x830000, 0xff000f, &fmt_RRR },
	{ "movgez", 0xb30000, 0xff000f, &fmt_RRR },
	{ "movi",   0x00a002, 0x00f00f, &fmt_RRI8_i12 },
	{ "movltz", 0xa30000, 0xff000f, &fmt_RRR },
	{ "movnez", 0x930000, 0xff000f, &fmt_RRR },
	{ "mul16s", 0xd10000, 0xff000f, &fmt_RRR },
	{ "mul16u", 0xc10000, 0xff000f, &fmt_RRR },
	{ "mull",   0x820000, 0xff000f, &fmt_RRR },
	{ "neg",    0x600000, 0xff0f0f, &fmt_RRR_2rr },
	{ "nsa",    0x40e000, 0xfff00f, &fmt_RRR_2r },
	{ "nsau",   0x40f000, 0xfff00f, &fmt_RRR_2r },
	{ "nop",    0x0020f0, 0xffffff, &fmt_NONE },
	{ "or",     0x200000, 0xff000f, &fmt_RRR },
	{ "ret",    0x000080, 0xffffff, &fmt_NONE, DISASM_BRANCH_RET },
	{ "rfe",    0x003000, 0xffffff, &fmt_NONE, DISASM_BRANCH_RET },
	{ "rfi",    0x003010, 0xfff0ff, &fmt_RRR_1imm, DISASM_BRANCH_RET },
	{ "rsil",   0x006000, 0xfff00f, &fmt_RRR_immr },
	{ "rsr",    0x030000, 0xff000f, &fmt_RSR },
	{ "rsync",  0x002010, 0xffffff, &fmt_NONE },
	{ "s8i",    0x004002, 0x00f00f, &fmt_RRI8_disp },
	{ "s16i",   0x005002, 0x00f00f, &fmt_RRI8_disp16 },
	{ "s32i",   0x006002, 0x00f00f, &fmt_RRI8_disp32 },
	{ "sll",    0xa10000, 0xff00ff, &fmt_RRR_sll },
	{ "slli",   0x010000, 0xef000f, &fmt_RRR_slli },
	{ "sra",    0xb10000, 0xff0f0f, &fmt_RRR_2rr },
	{ "srai",   0x210000, 0xef000f, &fmt_RRR_srai },
	{ "src",    0x810000, 0xff000f, &fmt_RRR },
	{ "srl",    0x910000, 0xff0f0f, &fmt_RRR_2rr },
	{ "srli",   0x410000, 0xff000f, &fmt_RRR_sh },
	{ "ssa8b",  0x403000, 0xfff0ff, &fmt_RRR_ssa },
	{ "ssa8l",  0x402000, 0xfff0ff, &fmt_RRR_ssa },
	{ "ssai",   0x404000, 0xfff0ef, &fmt_RRR_ssai },
	{ "ssl",    0x401000, 0xfff0ff, &fmt_RRR_ssa },
	{ "ssr",    0x400000, 0xfff0ff, &fmt_RRR_ssa },
	{ "sub",    0xc00000, 0xff000f, &fmt_RRR },
	{ "subx2",  0xd00000, 0xff000f, &fmt_RRR },
	{ "subx4",  0xe00000, 0xff000f, &fmt_RRR },
	{ "subx8",  0xf00000, 0xff000f, &fmt_RRR },
	{ "waiti",  0x007000, 0xfff0ff, &fmt_RRR_1imm },
	{ "wdtlb",  0x50e000, 0xfff00f, &fmt_RRR_2r },
	{ "witlb",  0x506000, 0xfff00f, &fmt_RRR_2r },
	{ "wsr",    0x130000, 0xff000f, &fmt_RSR },
	{ "xor",    0x300000, 0xff000f, &fmt_RRR },
	{ "xsr",    0x610000, 0xff000f, &fmt_RSR },
//	{ "movi*",   0x000001, 0x000000, &fmt_NONE },

	{ "add.n",   0x000a, 0x000f, &fmt_RRRN },
	{ "addi.n",  0x000b, 0x000f, &fmt_RRRN_addi },
	{ "beqz.n",  0x008c, 0x00cf, &fmt_RI6 },
	{ "bnez.n",  0x00cc, 0x00cf, &fmt_RI6 },
	{ "mov.n",   0x000d, 0xf00f, &fmt_RRRN_2r },
	{ "break.n", 0xf02d, 0xf0ff, &fmt_RRRN },
	{ "ret.n",   0xf00d, 0xffff, &fmt_NNONE, DISASM_BRANCH_RET },
	{ "l32i.n",  0x0008, 0x000f, &fmt_RRRN_disp },
	{ "movi.n",  0x000c, 0x008f, &fmt_RI7 },
	{ "nop.n",   0xf03d, 0xffff, &fmt_NNONE },
	{ "s32i.n",  0x0009, 0x000f, &fmt_RRRN_disp },

	{ NULL }
};

static inline uint32_t bitfield(uint32_t op, int size, int shift)
{
	return (op >> shift) & ((1<<size)-1);
}

- (int)disassembleSingleInstruction:(DisasmStruct *)disasm usingProcessorMode:(NSUInteger)mode {
	if (disasm->bytes == NULL) return DISASM_UNKNOWN_OPCODE;
	uint32_t insn = [self readWordAt:disasm->virtualAddr];
	const struct Instr *i = opcodes;
	for(;;i++) {
		if(i->mnemonic == NULL)
			return DISASM_UNKNOWN_OPCODE;

		if((insn & i->mask) == i->opcode)
			break;
	}

	disasm->instruction.branchType = i->branchType;
	disasm->instruction.addressValue = 0;
	disasm->instruction.pcRegisterValue = disasm->virtualAddr + i->format->length;
	strcpy(disasm->instruction.mnemonic, i->mnemonic);
	
	int op;
	for(op=0;op < DISASM_MAX_OPERANDS;op++) {
		DisasmOperand *out = &disasm->operand[op];
		out->type = DISASM_OPERAND_NO_OPERAND;
	}

	for(op=0;op<4;op++) {
		const struct Operand *in = &i->format->operands[op];
		DisasmOperand *out = &disasm->operand[op];

		if(in->type == Operand_NONE)
			break;
		
		uint32_t uval = bitfield(insn, in->size, in->rshift);
		if(in->size2)
			uval |= bitfield(insn, in->size2, in->rshift2) << in->size;

		if(in->signext || (in->type >= Operand_RELA)) {
			if(uval & (1 << (in->size + in->size2-1))) {
				// sign-extend
				uval |= 0xffffffff << (in->size + in->size2);
			}
		}

		int64_t val = (((int64_t)(int32_t)uval) << in->vshift) + (int64_t)in->off;
		if(in->xlate)
			val = in->xlate(val);

		switch(in->type) {
		case Operand_REG:
			out->type = DISASM_OPERAND_REGISTER_TYPE;
			if(val & 0x1000) {// special register
				out->type |= DISASM_BUILD_REGISTER_CLS_MASK(RegClass_SpecialRegister0 + (val / DISASM_MAX_REG_INDEX));
				out->type |= DISASM_BUILD_REGISTER_INDEX_MASK(val % DISASM_MAX_REG_INDEX);
			} else {
				out->type |= DISASM_BUILD_REGISTER_CLS_MASK(RegClass_GeneralPurposeRegister);
				out->type |= DISASM_BUILD_REGISTER_INDEX_MASK(val);
			}
			break;

		case Operand_IMM:
			out->type = DISASM_OPERAND_CONSTANT_TYPE | DISASM_OPERAND_ABSOLUTE;
			out->immediateValue = val;
			break;

		case Operand_MEM:
			out->type = DISASM_OPERAND_MEMORY_TYPE;
			//out->type |= DISASM_BUILD_REGISTER_CLS_MASK(RegClass_GeneralPurposeRegister);
			//((disasm->virtualAddr + 3) & (~3)) + val;
			out->immediateValue = 
			out->memory.displacement = ((disasm->virtualAddr + 3) & (~3)) + val * 4;
			[_file setType:Type_Int32 atVirtualAddress: out->immediateValue forLength: 4];
			break;

		case Operand_RELA:
			out->type = DISASM_OPERAND_CONSTANT_TYPE | DISASM_OPERAND_RELATIVE;
			disasm->instruction.addressValue = 
			out->memory.displacement = 
			out->immediateValue = disasm->virtualAddr + val + 4;
			out->isBranchDestination = 1;
			break;

		case Operand_RELAL:
			out->type = DISASM_OPERAND_CONSTANT_TYPE | DISASM_OPERAND_RELATIVE;
			out->immediateValue = (disasm->virtualAddr & (~3)) + 4 + (val<<2);
			break;

		case Operand_RELU:
			out->type = DISASM_OPERAND_CONSTANT_TYPE | DISASM_OPERAND_RELATIVE;
			// FIXME
			break;

		case Operand_MEM_INDEX:
			out->type = DISASM_OPERAND_MEMORY_TYPE;
			// FIXME
			break;

		default:
			break;
		}
	}

	return i->format->length; 
}

- (BOOL)instructionHaltsExecutionFlow:(DisasmStruct *)disasm {
	return NO;
}

- (void)performBranchesAnalysis:(DisasmStruct *)disasm computingNextAddress:(Address *)next andBranches:(NSMutableArray *)branches forProcedure:(NSObject<HPProcedure> *)procedure basicBlock:(NSObject<HPBasicBlock> *)basicBlock ofSegment:(NSObject<HPSegment> *)segment calledAddresses:(NSMutableArray *)calledAddresses callsites:(NSMutableArray *)callSitesAddresses {

}

- (void)performInstructionSpecificAnalysis:(DisasmStruct *)disasm forProcedure:(NSObject<HPProcedure> *)procedure inSegment:(NSObject<HPSegment> *)segment {

}

- (void)performProcedureAnalysis:(NSObject<HPProcedure> *)procedure basicBlock:(NSObject<HPBasicBlock> *)basicBlock disasm:(DisasmStruct *)disasm {

}

- (void)updateProcedureAnalysis:(DisasmStruct *)disasm {

}

- (NSObject<HPASMLine> *)buildMnemonicString:(DisasmStruct *)disasm inFile:(NSObject<HPDisassembledFile> *)file {
	NSObject<HPHopperServices> *services = _cpu.hopperServices;
	NSObject<HPASMLine> *line = [services blankASMLine];
	NSString *mnemonic = @(disasm->instruction.mnemonic);
	BOOL isJump = (disasm->instruction.branchType != DISASM_BRANCH_NONE);
	[line appendMnemonic:mnemonic isJump:isJump];
	return line;
}

static inline int firstBitIndex(uint64_t mask) {
    for (int i=0, j=1; i<64; i++, j<<=1) {
        if (mask & j) {
            return i;
        }
    }
    return -1;
}

static inline RegClass regClassFromType(uint64_t type) {
    return (RegClass) firstBitIndex(DISASM_GET_REGISTER_CLS_MASK(type));
}

static inline int regIndexFromType(uint64_t type) {
    return firstBitIndex(DISASM_GET_REGISTER_INDEX_MASK(type));
}

- (NSObject<HPASMLine> *)buildOperandString:(DisasmStruct *)disasm forOperandIndex:(NSUInteger)operandIndex inFile:(NSObject<HPDisassembledFile> *)file raw:(BOOL)raw {
	if (operandIndex >= DISASM_MAX_OPERANDS) return nil;
	DisasmOperand *operand = &disasm->operand[operandIndex];
	if (operand->type == DISASM_OPERAND_NO_OPERAND) return nil;
	
	ArgFormat format = [file formatForArgument:operandIndex atVirtualAddress:disasm->virtualAddr];
	NSObject<HPHopperServices> *services = _cpu.hopperServices;
	NSObject<HPASMLine> *line = [services blankASMLine];

	if (operand->type & DISASM_OPERAND_CONSTANT_TYPE) {
		if (disasm->instruction.branchType) {
			if (format == Format_Default) format = Format_Address;
		} else {
//			[line appendRawString:@"#"];
		}
		[line append:[file formatNumber:operand->immediateValue at:disasm->virtualAddr usingFormat:format andBitSize:32]];

	} else if (operand->type & DISASM_OPERAND_REGISTER_TYPE) {
		// FIXME, this doesn't match gas syntax for special registers
		RegClass regCls = regClassFromType(operand->type);
		int regIdx = regIndexFromType(operand->type);
		[line appendRegister:[_cpu registerIndexToString:regIdx
						ofClass:regCls
						withBitSize:32
						position:DISASM_LOWPOSITION
						andSyntaxIndex:file.userRequestedSyntaxIndex ]];

	} else if (operand->type & DISASM_OPERAND_MEMORY_TYPE) {
		if(false) {
		} else {
			if([file sectionForVirtualAddress:operand->immediateValue]) {
				uint32_t val = [file readUInt32AtVirtualAddress:operand->immediateValue];
				[line appendRawString:@"="];
				[line append:[file formatNumber:val at:disasm->virtualAddr usingFormat:format andBitSize:32]];
			}
		}

	} else {
		[line appendRawString:@"?"];
	}
	/*	
	[line appendRawString:@":"];
	[line append:[file formatNumber:operand->userData[0] at:disasm->virtualAddr usingFormat:Format_Hexadecimal andBitSize:32]];
	[line appendRawString:@":"];
	[line append:[file formatNumber:operand->userData[1] at:disasm->virtualAddr usingFormat:Format_Hexadecimal andBitSize:32]];
	*/
    
	[line setIsOperand:operandIndex startingAtIndex:0];

	return line;
}

- (NSObject<HPASMLine> *)buildCompleteOperandString:(DisasmStruct *)disasm inFile:(NSObject<HPDisassembledFile> *)file raw:(BOOL)raw {
	NSObject<HPHopperServices> *services = _cpu.hopperServices;

	NSObject<HPASMLine> *line = [services blankASMLine];

	for (int op_index=0; op_index <= DISASM_MAX_OPERANDS; op_index++) {
		NSObject<HPASMLine> *part = [self buildOperandString:disasm forOperandIndex:op_index inFile:file raw:raw];
		if (part == nil) break;
		if (op_index) [line appendRawString:@", "];
		[line append:part];
	}

	return line;
}


// Decompiler

- (BOOL)canDecompileProcedure:(NSObject<HPProcedure> *)procedure {
	return NO;
}

- (Address)skipHeader:(NSObject<HPBasicBlock> *)basicBlock ofProcedure:(NSObject<HPProcedure> *)procedure {
	return basicBlock.from;
}

- (Address)skipFooter:(NSObject<HPBasicBlock> *)basicBlock ofProcedure:(NSObject<HPProcedure> *)procedure {
	return basicBlock.to;
}

- (ASTNode *)rawDecodeArgumentIndex:(int)argIndex
				ofDisasm:(DisasmStruct *)disasm
				ignoringWriteMode:(BOOL)ignoreWrite
				usingDecompiler:(Decompiler *)decompiler {
	return nil;
}

- (ASTNode *)decompileInstructionAtAddress:(Address)a
				disasm:(DisasmStruct *)d
				addNode_p:(BOOL *)addNode_p
				usingDecompiler:(Decompiler *)decompiler {
	return nil;
}

// Assembler

- (NSData *)assembleRawInstruction:(NSString *)instr atAddress:(Address)addr forFile:(NSObject<HPDisassembledFile> *)file withCPUMode:(uint8_t)cpuMode usingSyntaxVariant:(NSUInteger)syntax error:(NSError **)error {
	return nil;
}

- (BOOL)instructionCanBeUsedToExtractDirectMemoryReferences:(DisasmStruct *)disasmStruct {
	return YES;
}

- (BOOL)instructionOnlyLoadsAddress:(DisasmStruct *)disasmStruct {
	return NO;
}

- (BOOL)instructionManipulatesFloat:(DisasmStruct *)disasmStruct {
	return NO;
}

- (BOOL)instructionConditionsCPUModeAtTargetAddress:(DisasmStruct *)disasmStruct resultCPUMode:(uint8_t *)cpuMode {
	return NO;
}

- (uint8_t)cpuModeForNextInstruction:(DisasmStruct *)disasmStruct {
	return 0;
}

- (BOOL)instructionMayBeASwitchStatement:(DisasmStruct *)disasmStruct {
	return NO;
}

@end