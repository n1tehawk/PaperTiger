unit imagecleaner;

{ Image cleaning unit; to be used to straighten up/deskew, despeckle etc images
  so OCR is more accurate.

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

interface

uses
  Classes, SysUtils,
  processutils, tigerutil,
  magick_wand, ImageMagick, fpimage, ocr;

type

  { TImageCleaner }

  TImageCleaner = class(TObject)
  private
    FImageFile: string;
    FLanguage: string;
    // Tests page layout by running a scan.
    // Returns OCR recognition score (percentage) as well as the
    // approximate number of correctly-spelled words found
    function CheckRecognition(ImageFile: string; var CorrectWords: integer): integer;
    // Returns degrees image needs to be turned to end right-side-up
    function DetectRotation: integer;
    // Rotates source image to destination image over specified number of degrees clockwise
    // Returns true if succesful
    function Rotate(Degrees: integer; SourceFile, DestinationFile: string): boolean;
  public
    // Reads image, performs OCR tests on it to figure out if it needs to be rotated.
    // Rotates image if needed
    // Returns number of degrees the image has been turned,
    // e.g. -90: image rotated counterclockwise 90 degrees
    function DetectApplyRotation: integer;
    // Input image
    property ImageFile: string write FImageFile;
    // Language to use for OCR, e.g. eng for English, nld for Dutch
    property Language: string read FLanguage write FLanguage;
    constructor Create;
    destructor Destroy; override;
  end;

implementation

// Common constants etc:
{$i tigercommondefs.inc}

procedure ThrowWandException(wand: PMagickWand);
var
  description: PChar;
  severity: ExceptionType;
begin
  description := MagickGetException(wand, @severity);
  TigerLog.WriteLog(etError,Format('An error ocurred. Description: %s', [description]));
  description := MagickRelinquishMemory(description);
  Abort;
end;

function TImageCleaner.CheckRecognition(ImageFile: string; var CorrectWords: integer): integer;
const
  DetectLog = '/tmp/detectlog.txt';
var
  i, LinesRead: integer;
  TempOCR: TOCR;
  ResList: TStringList;
  WordsTotal, WordsWrong: integer;
begin
  result:=-1; //Negative(!) recognition rate: fail by default
  TempOCR:=TOCR.Create;
  ResList:=TStringList.Create;
  try
    TempOCR.ImageFile:=ImageFile;
    TempOCR.Language:=FLanguage;
    TempOCR.RecognizeText(sofPlainText);
    // Now open the text file to check effectiveness
    if ExecuteCommand(TextDetectCommand+' "'+TempOCR.OCRFile+'"',false)<>0 then
    begin
      // hardcoded results in /tmp/detectlog.txt
      ResList.LoadFromFile(DetectLog);
      LinesRead:=0;
      for i:=0 to ResList.Count-1 do
      begin
        // Ignore comments starting with #
        if pos('#',trim(Reslist[i]))<>1 then
        begin
          case LinesRead of
          0:
            begin
              // Total wordcount
              WordsTotal:=strtointdef(Trim(ResList[i]),-1);
              LinesRead:=LinesRead+1;
            end;
          1:
            begin
              // Number of spelling errors/incorrectly spelled words
              try
                WordsWrong:=strtointdef(Trim(ResList[i]),0);
                CorrectWords:=WordsTotal-WordsWrong;
                if CorrectWords<0 then CorrectWords:=0;
                Result:=CorrectWords div WordsTotal;
              except
                // keep result at -1
              end;
              LinesRead:=LinesRead+1;
            end;
          else
            begin
              TigerLog.WriteLog(etWarning,'TImageCleaner.CheckRecognition: unknown detect line: '+ResList[i]);
            end;
          end;
        end;
      end;
    end;
  finally
    TempOCR.Free;
    ResList.Free;
  end;
end;

{ TImageCleaner }
function TImageCleaner.DetectRotation: integer;
const
  MinWords = 10; //Below this number, the image probably has no valid text
var
  DetectedRotation: integer;
  RotatedImage: string;
  Options: string;
  Rotation: integer;
  Score: integer;
  TopScore: integer;
  CorrectWords: integer;
begin
  //todo: first convert image to 300dpi, lineart if it isn't already
  Result := 0;
  Rotation:=0;
  while Rotation <= 270 do
  begin
    if Rotation = 0 then
      RotatedImage:=FImageFile
    else
      RotatedImage:=GetTempFileName('',inttostr(Rotation));
    Rotate(Rotation,FImageFile, RotatedImage);
    Score:=CheckRecognition(RotatedImage,CorrectWords);
    if Score>TopScore then
    begin
      TopScore:=Score;
      DetectedRotation:=Rotation;
    end;
    Rotation:=Rotation + 90;
  end;
  result := DetectedRotation;
end;

constructor TImageCleaner.Create;
begin

end;

destructor TImageCleaner.Destroy;
begin
  inherited Destroy;
end;

function TImageCleaner.Rotate(Degrees: integer; SourceFile,
  DestinationFile: string): boolean;
var
  status: MagickBooleanType;
  wand: PMagickWand;
begin
  wand := NewMagickWand;
  try
    status := MagickReadImage(wand, PChar(SourceFile));
    if (status = MagickFalse) then ThrowWandException(wand);
    MagickRotateImage(wand,nil,Degrees);
    if (status = MagickFalse) then ThrowWandException(wand);
    status := MagickWriteImages(wand, PChar(DestinationFile), MagickTrue);
    if (status = MagickFalse) then ThrowWandException(wand);
    result := not(status=MagickFalse);
  finally
    wand := DestroyMagickWand(wand);
    MagickWandTerminus;
  end;
end;

function TImageCleaner.DetectApplyRotation: integer;
var
  Degrees:integer;
begin
  Degrees:=DetectRotation;
  try
    //todo: actual turning
  except
    Degrees:=0;
    //error message
  end;
  result:=Degrees;

end;

end.
