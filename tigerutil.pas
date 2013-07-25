unit tigerutil;

{ Utility functions such as logging support.

  Copyright (c) 2012-2013 Reinier Olislagers

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
}



{$i tigerserver.inc}
{$IFDEF MSWINDOWS}
{$R fclel.res}//needed for message files to get Windows to display event log contents correctly
// Not needed for *nix
{$ENDIF}

interface

uses
  Classes, SysUtils, eventlog;

type
  { TLogger }
  TLogger = class(TObject)
  private
    FLog: TEventLog; //Logging/debug output to syslog/eventlog
  public
    property EventLog: TEventLog read FLog;
    // Write to log and optionally console with seriousness etInfo
    procedure WriteLog(Message: string; ToConsole: boolean = False);
    // Write to log and optionally console with specified seriousness
    procedure WriteLog(EventType: TEventType; Message: string;
      ToConsole: boolean = False);
    constructor Create;
    destructor Destroy; override;
  end;

{todo: need translation array:
- tesseract language code (nld, eng, fra...)
- cuneiform language code (=ISO x letter code):
cuneiform -l
Cuneiform for Linux 1.1.0
...
eng ger fra rus swe spa ita ruseng ukr srp hrv pol
dan por dut cze rum hun bul slv lav lit est tur
- LANG code for Linux environment for Hunspell
and lookup/translation
}
var
  TigerLog: TLogger; //Created by unit initialization so available for every referencing unit

// Copy file to same or other filesystem, overwriting existing files
function FileCopy(Source, Target: string): boolean;

// Delete length characters from starting position from a stream
procedure DeleteFromStream(Stream: TStream; Start, Length: Int64);

// Searches for SearchFor in Stream starting at Start.
// Returns -1 or position in stream (0-based)
function FindInStream(Stream: TStream; Start: int64; SearchFor: string): int64;

//Shows non-debug messages on screen; also shows debug messages if DEBUG defined
procedure infoln(Message: string; Level: TEventType);

implementation
uses math;

function FileCopy(Source, Target: string): boolean;
const
   ChunkSize  : Longint = 8192; { copy in 8K chunks }
var
   CopyBuffer   : Pointer; { buffer for copying }
   BytesCopied  : Longint;
   SourceHdl, DestinationHdl : Integer; { handles }
   TargetTF  : TFileName; { holder for expanded target name }

begin
  result:=false;
  TargetTF := Target;
  GetMem(CopyBuffer, ChunkSize); { allocate the buffer }
  try
   SourceHdl := FileOpen(Source, fmShareDenyWrite); { open source file }
   if SourceHdl < 0 then
     //raise EFOpenError.CreateFmt('Error: Can''t open file!', [SourceHdl]);
     exit;

   try
     DestinationHdl := FileCreate(TargetTF); { create output file; overwrite existing }
     if DestinationHdl < 0 then
       //raise EFCreateError.CreateFmt('Error: Can''t create file!', [TargetTF]);
       exit;
     try
       repeat
         BytesCopied := FileRead(SourceHdl, CopyBuffer^, ChunkSize); { read chunk }
         if BytesCopied > 0  {if we read anything... }
            then FileWrite(DestinationHdl, CopyBuffer^, BytesCopied); { ...write chunk }
       until BytesCopied < ChunkSize; { until we run out of chunks }
     finally
       FileClose(DestinationHdl); { close the TargetTF file }
     end;
   finally
     FileClose(SourceHdl); { close the source file }
   end;
  finally
   FreeMem(CopyBuffer, ChunkSize); { free the buffer }
  end;
  result:=true;
end;

procedure DeleteFromStream(Stream: TStream; Start, Length: Int64);
// Source:
// http://stackoverflow.com/questions/9598032/is-it-possible-to-delete-bytes-from-the-beginning-of-a-file
var
  Buffer: Pointer;
  BufferSize: Integer;
  BytesToRead: Int64;
  BytesRemaining: Int64;
  SourcePos, DestPos: Int64;
begin
  SourcePos := Start+Length;
  DestPos := Start;
  BytesRemaining := Stream.Size-SourcePos;
  BufferSize := Min(BytesRemaining, 1024*1024*16);//no bigger than 16MB
  GetMem(Buffer, BufferSize);
  try
    while BytesRemaining>0 do begin
      BytesToRead := Min(BufferSize, BytesRemaining);
      Stream.Position := SourcePos;
      Stream.ReadBuffer(Buffer^, BytesToRead);
      Stream.Position := DestPos;
      Stream.WriteBuffer(Buffer^, BytesToRead);
      inc(SourcePos, BytesToRead);
      inc(DestPos, BytesToRead);
      dec(BytesRemaining, BytesToRead);
    end;
    Stream.Size := DestPos;
  finally
    FreeMem(Buffer);
  end;
end;

function FindInStream(Stream: TStream; Start: int64; SearchFor: string): int64;
// Adapted from
// http://wiki.lazarus.freepascal.org/Rosetta_Stone#Finding_all_occurrences_of_some_bytes_in_a_file
var
  a: array of byte;
  BlockArray: array of byte; //Gets a block of bytes from the stream
  BlockSize:integer = 1024*1024;
  ReadSize:integer;
  fPos:Int64;
  FifoBuff:array of byte; //Window into blockarray, used to match SearchFor
  FifoStart,FifoEnd,SearchLen,lpbyte:integer;

  function CheckPos: int64;
  var
    l,p:integer;
  begin
    result:=-1;
    p := FifoStart;
    for l := 0 to pred(SearchLen) do
    begin
      if a[l] <> FifoBuff[p] then exit; //match broken off
      //p := (p+1) mod SearchLen,   the if seems quicker
      inc(p);
      if p >= SearchLen then p := 0;
    end;
    result:=(fpos-SearchLen);
  end;

begin
  SetLength(a,length(SearchFor));
  Move(Searchfor[1], a[0], Length(Searchfor)); //todo check if this shouldn't be a^

  setlength(BlockArray,BlockSize);
  Stream.Position:=Start;
  ReadSize := Stream.Read(BlockArray[0],Length(BlockArray));
  SearchLen := length(a);
  if SearchLen > length(BlockArray) then
    raise Exception.CreateFmt('FindInStream: search term %s larger than blocksize',[SearchFor]);
  if ReadSize < SearchLen then exit; //can't be in there so quit

  setlength(FifoBuff,SearchLen);
  move(BlockArray[0],FifoBuff[0],SearchLen);
  fPos:=0;
  FifoStart:=0;
  FifoEnd:=SearchLen-1;
  result:=CheckPos;
  if result>-1 then
    exit; //found it
  while ReadSize > 0 do
  begin
    for lpByte := 0 to pred(ReadSize) do
    begin
      inc(FifoStart); if FifoStart>=SearchLen then FifoStart := 0;
      inc(FifoEnd); if FifoEnd>=SearchLen then FifoEnd := 0;
      FifoBuff[FifoEnd] := BlockArray[lpByte];
      inc(fPos);
      result:=CheckPos;
      if result>-1 then
        exit; //found it
    end;
    ReadSize := Stream.Read(BlockArray[0],Length(BlockArray));
  end;
end;

procedure infoln(Message: string; Level: TEventType);
var
  Seriousness: string;
begin
  case Level of
    etCustom: Seriousness := 'Custom:';
    etDebug: Seriousness := 'Debug:';
    etInfo: Seriousness := 'Info:';
    etWarning: Seriousness := 'WARNING:';
    etError: Seriousness := 'ERROR:';
    else
      Seriousness := 'UNKNOWN CATEGORY!!:'
  end;
  if (Level <> etDebug) then
  begin
    if AnsiPos(LineEnding, Message) > 0 then
      writeln(''); //Write an empty line before multiline messagse
    writeln(Seriousness + ' ' + Message); //we misuse this for info output
    sleep(200); //hopefully allow output to be written without interfering with other output
  end
  else
  begin
      {$IFDEF DEBUG}
      {DEBUG conditional symbol is defined using e.g.
      Project Options/Other/Custom Options using -dDEBUG}
    if AnsiPos(LineEnding, Message) > 0 then
      writeln(''); //Write an empty line before multiline messagse
    writeln(Seriousness + ' ' + Message); //we misuse this for info output
    sleep(200); //hopefully allow output to be written without interfering with other output
      {$ENDIF DEBUG}
  end;
end;

{ TLogger }

procedure TLogger.WriteLog(Message: string; ToConsole: boolean = False);
begin
  FLog.Log(etInfo, Message);
  if ToConsole then
    infoln(Message, etinfo);
end;

procedure TLogger.WriteLog(EventType: TEventType; Message: string;
  ToConsole: boolean = False);
begin
  // Only log debug level if compiled as a debug build in order to cut down on logging
  {$IFDEF DEBUG}
  if 1 = 1 then
  {$ELSE}
    if EventType <> etDebug then
  {$ENDIF}
    begin
      FLog.Log(EventType, Message);
      if ToConsole then
        infoln(Message, etinfo);
    end;
  {$IFDEF DEBUG}
  // By setting active to false, we try to force a log write. Next log attempt will set active to true again
  FLog.Active := False;
  {$ENDIF}
end;

constructor TLogger.Create;
begin
  FLog := TEventLog.Create(nil);
  FLog.LogType := ltSystem; //eventlog/syslog, not log to file
  FLog.RegisterMessageFile('');
  //specify Windows should use the binary to look up formatting strings
  FLog.RaiseExceptionOnError := False; //Don't throw exceptions on log errors.
  FLog.Active := True;
end;

destructor TLogger.Destroy;
begin
  FLog.Active := False; //save WriteLog text
  FLog.Free;
  inherited Destroy;
end;

initialization
  begin
    TigerLog := TLogger.Create;
  end;

finalization
  begin
    TigerLog.Free;
  end;
end.
