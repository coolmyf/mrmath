// ###################################################################
// #### This file is part of the mathematics library project, and is
// #### offered under the licence agreement described on
// #### http://www.mrsoft.org/
// ####
// #### Copyright:(c) 2011, Michael R. . All rights reserved.
// ####
// #### Unless required by applicable law or agreed to in writing, software
// #### distributed under the License is distributed on an "AS IS" BASIS,
// #### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// #### See the License for the specific language governing permissions and
// #### limitations under the License.
// ###################################################################


unit CPUFeatures;

// unit to determine some cpu features

interface

function IsSSE3Present : boolean;
function IsAVXPresent : boolean;
function IsFMAPresent : boolean;
function IsHardwareRNDSupport : boolean;
function IsHardwareRDSeed : boolean;

function GetCurrentProcessorNumber : LongWord; register;

implementation

// ##############################################################
// #### feature detection code
// ##############################################################

type
  TRegisters = record
    EAX,
    EBX,
    ECX,
    EDX: Cardinal;
  end;

{$IFDEF FPC} {$ASMMODE intel} {$S-} {$ENDIF}

{$IFDEF CPUX64}
{$DEFINE x64}
{$ENDIF}
{$IFDEF cpux86_64}
{$DEFINE x64}
{$ENDIF}
{$IFDEF x64}

function IsCPUID_Available : boolean;
begin
     Result := true;
end;

procedure GetCPUID(Param: Cardinal; out Registers: TRegisters);
var iRBX, iRDI : int64;
{$IFDEF FPC}
begin
{$ENDIF}
asm
   mov iRBX, rbx;
   mov iRDI, rdi;

//   .pushnv rbx;                        {save affected registers}
//   .pushnv rdi;

   MOV     RDI, Registers
   MOV     EAX, Param;
   XOR     RBX, RBX                    {clear EBX register}
   XOR     RCX, RCX                    {clear ECX register}
   XOR     RDX, RDX                    {clear EDX register}
   DB $0F, $A2                         {CPUID opcode}
   MOV     TRegisters(RDI).&EAX, EAX   {save EAX register}
   MOV     TRegisters(RDI).&EBX, EBX   {save EBX register}
   MOV     TRegisters(RDI).&ECX, ECX   {save ECX register}
   MOV     TRegisters(RDI).&EDX, EDX   {save EDX register}

   // epilog
   mov rbx, iRBX;
   mov rdi, IRDI;
{$IFDEF FPC}
end;
{$ENDIF}
end;

{$ELSE}

function IsCPUID_Available: Boolean; register;
{$IFDEF FPC} begin {$ENDIF}
asm
   PUSHFD                 {save EFLAGS to stack}
   POP     EAX            {store EFLAGS in EAX}
   MOV     EDX, EAX       {save in EDX for later testing}
   XOR     EAX, $200000;  {flip ID bit in EFLAGS}
   PUSH    EAX            {save new EFLAGS value on stack}
   POPFD                  {replace current EFLAGS value}
   PUSHFD                 {get new EFLAGS}
   POP     EAX            {store new EFLAGS in EAX}
   XOR     EAX, EDX       {check if ID bit changed}
   JZ      @exit          {no, CPUID not available}
   MOV     EAX, True      {yes, CPUID is available}
@exit:
end;
{$IFDEF FPC} end; {$ENDIF}

procedure GetCPUID(Param: Cardinal; var Registers: TRegisters);
{$IFDEF FPC} begin {$ENDIF}
asm
   PUSH    EBX                         {save affected registers}
   PUSH    EDI
   MOV     EDI, Registers
   XOR     EBX, EBX                    {clear EBX register}
   XOR     ECX, ECX                    {clear ECX register}
   XOR     EDX, EDX                    {clear EDX register}
   DB $0F, $A2                         {CPUID opcode}
   MOV     TRegisters(EDI).&EAX, EAX   {save EAX register}
   MOV     TRegisters(EDI).&EBX, EBX   {save EBX register}
   MOV     TRegisters(EDI).&ECX, ECX   {save ECX register}
   MOV     TRegisters(EDI).&EDX, EDX   {save EDX register}
   POP     EDI                         {restore registers}
   POP     EBX
end;
{$IFDEF FPC} end; {$ENDIF}

{$ENDIF}


function GetCurrentProcessorNumber : LongWord; register; // stdcall; external 'Kernel32.dll';
{$IFDEF FPC}
begin
{$ENDIF}
asm
   mov eax, 1;
   DB $0F, $A2;  //cpuid;
   shr ebx, 24;
   mov eax, ebx;
{$IFDEF FPC}
end;
{$ENDIF}
end;

function IsSSE3Present : boolean;
var reg : TRegisters;
begin
     Result := False;

     if IsCPUID_Available then
     begin
          GetCPUID($00000001, reg);

          // first bit of ECX
          Result := (reg.ECX and $00000001) <> 0;
     end;
end;

// ###########################################
// #### Local check for AVX support according to
// from https://software.intel.com/en-us/blogs/2011/04/14/is-avx-enabled
function isAvxOSSupported : boolean; {$IFDEF FPC}assembler;{$ENDIF}
asm
   {$IFDEF x64}
   push rbx;
   {$ELSE}
   push ebx;
   {$ENDIF}
   
   xor eax, eax;
   cpuid;
   cmp eax, 1;
   jb @not_supported;

   mov eax, 1;
   cpuid;

   and ecx, $018000000; // check 27 bit (OS uses XSAVE/XRSTOR)
   cmp ecx, $018000000; // and 28 (AVX supported by CPU)
   jne @not_supported;
   
   xor ecx, ecx ; // XFEATURE_ENABLED_MASK/XCR0 register number = 0
   db $0F, $01, $D0; //xgetbv ; // XFEATURE_ENABLED_MASK register is in edx:eax
   and eax, $6; //110b
   cmp eax, $6; //110b ; check the AVX registers restore at context switch
   jne @not_supported;
   mov eax, 1
   jmp @@endProc;
   
   @not_supported:
   xor eax, eax;  // not supported -> return false

   @@endProc:

   {$IFDEF x64}
   pop rbx;
   {$ELSE}
   pop ebx;
   {$ENDIF}
end;

function IsAVXPresent : boolean;
var reg : TRegisters;
begin
     Result := False;

     if IsCPUID_Available then
     begin
          GetCPUID($00000001, reg);

          // check for AVX and check 27 bit (OS uses XSAVE/XRSTOR)
          Result := ((reg.ECX and (1 shl 28)) <> 0) and ((reg.ECX and (1 shl 27)) <> 0);

          if Result then
          begin
               try
                  Result := isAvxOSSupported;
               except
                     Result := False;
               end;
          end;
     end;
end;

function IsFMAPresent : boolean;
var reg : TRegisters;
begin
     Result := False;

     if IsCPUID_Available then
     begin
          GetCPUID($00000001, reg);

          // check for FMA and check 13 bit
          Result := ((reg.ECX and (1 shl 12)) <> 0) and ((reg.ECX and (1 shl 27)) <> 0);

          if Result then
          begin
               try
                  Result := isAvxOSSupported;
               except
                     Result := False;
               end;
          end;
     end;
end;

function IsHardwareRNDSupport : boolean;
var reg : TRegisters;
begin
     Result := False;
     if IsCPUID_Available then
     begin
          GetCPUID($00000001, reg);

          Result := (reg.ECX and $40000000) = $40000000;
     end;
end;

function IsHardwareRDSeed : boolean;
var reg : TRegisters;
begin
     Result := False;
     if IsCPUID_Available then
     begin
          GetCPUID($00000007, reg);

          Result := (reg.EBX and $40000) = $40000;
     end;
end;

end.
