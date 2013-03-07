unit tigercgimain;

{ CGI server part of papertiger.

  Copyright (c) 2013 Reinier Olislagers

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
{
If we send responses as JSON, always send an object or an array, not simply a string, float or integer.
Dates/times in JSON should be represented as ISO 8601 UTC (no timezone) formatted strings
}
{$i tigerserver.inc}

interface

uses
  SysUtils, Classes, httpdefs, fpjson, jsonparser, fpHTTP, fpWeb,
  tigerutil, tigerservercore;

type

  { TFPWebobsolete }

  TFPWebobsolete = class(TFPWebModule)
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
    procedure processdocumentRequest(Sender: TObject; ARequest: TRequest; //process document identified by documentid: OCR images, create PDF
      AResponse: TResponse; var Handled: Boolean);
    procedure scanRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //scans single image and adds it to document identified by documentid
    procedure serverinfoRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //lists server info (version etc)
    procedure unsupportedRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //handler for invalid requests
  private
    { private declarations }
    FTigerCore: TTigerServerCore;
  public
    { public declarations }
  end;

var
  FPWebobsolete: TFPWebobsolete;

implementation

{$R *.lfm}

{ TFPWebobsolete }




procedure TFPWebobsolete.DataModuleCreate(Sender: TObject);
begin
  FTigerCore := TTigerServerCore.Create;
end;

procedure TFPWebobsolete.DataModuleDestroy(Sender: TObject);
begin
  FTigerCore.Free;
end;



procedure TFPWebobsolete.processdocumentRequest(Sender: TObject;
  ARequest: TRequest; AResponse: TResponse; var Handled: Boolean);
var
  DocumentID: integer;
  InputJSON: TJSONObject;
  Message: string;
begin
  try
    // for uniformity, we expect a POST+a generic json tag, though we could have used e.g. docid directly
    //todo: adapt so InputJSON in URL is also accepted (for gets)
    InputJSON := TJSONParser.Create(ARequest.Content).Parse as TJSONObject;
    DocumentID := InputJSON.Integers['documentid'];
    //todo: figure out how to get resolution: it is encoded in the TIFF file; edentify bla.tif =>20130218144142.tif: TIFF 2472x3262 @ 300x300dpi (209x276mm) 1 bit, 1 channel
    // see e.g. http://stackoverflow.com/questions/7861600/get-horizontal-resolution-from-tif-in-c/7862187#7862187
    if FTigerCore.ProcessImages(DocumentID, 0)='' then
      raise Exception.Create('Got empty PDF for document '+inttostr(DocumentID));
  except
    Message := 'Processing images failed.';
    TigerLog.WriteLog(etDebug, 'processdocumentRequest: '+Message);
    AResponse.Contents.Add('<p>' + Message + '</p>');
    AResponse.Code:=500;
    AResponse.CodeText:=Message;
  end;
  Handled := True;
end;

procedure TFPWebobsolete.scanRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: boolean);
// Scans page and adds it to existing document
var
  DocumentID: integer;
  InputJSON: TJSONObject;
  Message: string;
  Success: boolean;
begin
  Success:=false;
  try
    // for uniformity, we expect a POST+a generic json tag, though we could have used e.g. docid directly
    //todo: adapt so InputJSON in URL is also accepted (for gets)
    InputJSON := TJSONParser.Create(ARequest.Content).Parse as TJSONObject;
    DocumentID := InputJSON.Integers['documentid'];
    Success := True;
  except
    Message := 'Scanning failed. No/invalid document ID.';
    TigerLog.WriteLog(etDebug, 'showDocumentRequest: '+Message);
    AResponse.Contents.Add('<p>' + Message + '</p>');
    AResponse.Code:=500;
    AResponse.CodeText:=Message;
  end;

  //todo implement resolution, language etc
  if Success then
  begin
    try
      Success:=(FTigerCore.ScanSinglePage(DocumentID)<>INVALIDID);
    except
      on E: Exception do
      begin
        Message := 'Scanning failed. Details: exception: '+E.Message;
        AResponse.Contents.Add('<p>' + Message + '</p>');
        AResponse.Code:=500;
        AResponse.CodeText:=Message;
        TigerLog.WriteLog(etError, 'scanRequest: ' + Message);
      end;
    end;
  end;

  if Success=false then
  begin
    Message :='Error scanning document for document ID '+inttostr(DocumentID);
    AResponse.Contents.Add('<p>'+Message+'</p>');
    AResponse.Code:=500;
    AResponse.CodeText:='Error scanning document for document ID '+inttostr(DocumentID);
    TigerLog.WriteLog(etError, 'scanRequest: ' + Message);
  end
  else
  begin
    AResponse.Contents.Add('<p>Scanning succeeded.</p>')
  end;
  Handled := True;
end;

procedure TFPWebobsolete.serverinfoRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: boolean);
var
  OutputJSON: TJSONObject;
begin
  AResponse.ContentType := 'application/json';
  OutputJSON := TJSONObject.Create();
  try
    OutputJSON.Add('serverinfo',FTigerCore.ServerInfo);
    AResponse.Contents.Add(OutputJSON.AsJSON);
  finally
    OutputJSON.Free;
  end;
  Handled := True;
end;

procedure TFPWebobsolete.unsupportedRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: boolean);
begin
  //todo add hyperlinks to all supported docs etc
  AResponse.Code:=404;
  AResponse.CodeText:='Unsupported method';
  AResponse.Contents.Add('<p>Unsupported method.</p>');
  //Tried with http://<server>/cgi-bin/tigercgi/unsupported?q=5
  AResponse.Contents.Add('<p>Command was: '+ARequest.Command+'</p>'); //gives nothing
  AResponse.Contents.Add('<p>Commandline was: '+ARequest.CommandLine+'</p>');
  AResponse.Contents.Add('<p>GetNextPathinfo: '+ARequest.GetNextPathInfo+'</p>'); //gives
  AResponse.Contents.Add('<p>Pathinfo: '+ARequest.PathInfo+'</p>'); //gives /unsupported
  AResponse.Contents.Add('<p>LocalPathPrefix: '+ARequest.LocalPathPrefix+'</p>');
  AResponse.Contents.Add('<p>ReturnedPathInfo: '+ARequest.ReturnedPathInfo+'</p>');
  AResponse.Contents.Add('<p>URI: '+ARequest.URI+'</p>'); //gives nothing
  AResponse.Contents.Add('<p>URL: '+ARequest.URL+'</p>'); //gives eg /cgi-bin/tigercgi/unsupported?q=5
  Handled := True;
end;

initialization
  // This registration will handle http://server/cgi-bin/tigercgi/obsolete/*
  RegisterHTTPModule('obsolete', TFPWebobsolete);
end.
