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
    procedure adddocumentRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean); //adds new empty document, returns documentid
    procedure deletedocumentRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //delete document identified by documentid
    procedure listRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //list all documents
    procedure processdocumentRequest(Sender: TObject; ARequest: TRequest; //process document identified by documentid: OCR images, create PDF
      AResponse: TResponse; var Handled: Boolean);
    procedure scanRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //scans single image and adds it to document identified by documentid
    procedure serverinfoRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //lists server info (version etc)
    procedure showdocumentRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //show PDF document identified by documentid
    procedure showimageRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //show image (TIFF) identified by documentid and imageorder
    procedure unsupportedRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //handler for invalid requests
    procedure uploadimageRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean); //upload image and process in order (after any existing images), adding it to document identified by documentid
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

//todo: use/add updatedocument that allows changing document name etc

procedure TFPWebobsolete.adddocumentRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: Boolean);
var
  DocumentID: integer;
  OutputJSON: TJSONObject;
begin
  DocumentID:=FTigerCore.AddDocument('Document ' +
    FormatDateTime('yyyymmddhhnnss', Now));
  if DocumentID=INVALIDID then
  begin
    AResponse.Code:=404;
    AResponse.CodeText:='Error inserting new document.';
    AResponse.Contents.Add('<p>Error inserting new document.</p>');
  end
  else
  begin
    AResponse.ContentType := 'application/json';
    OutputJSON := TJSONObject.Create();
    try
      OutputJSON.Add('documentid',DocumentID);
      AResponse.Contents.Add(OutputJSON.AsJSON);
    finally
      OutputJSON.Free;
    end;
  end;
  Handled := True;
end;

procedure TFPWebobsolete.DataModuleCreate(Sender: TObject);
begin
  FTigerCore := TTigerServerCore.Create;
end;

procedure TFPWebobsolete.DataModuleDestroy(Sender: TObject);
begin
  FTigerCore.Free;
end;

procedure TFPWebobsolete.deletedocumentRequest(Sender: TObject;
  ARequest: TRequest; AResponse: TResponse; var Handled: boolean);
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
    if DocumentID=INVALIDID then
      raise Exception.Create('Received invalid document ID.');
    if FTigerCore.DeleteDocument(DocumentID)=false then
      raise Exception.CreateFmt('FTigerCore.DeleteDocument failed to delete document ID %i',[DocumentID]);
  except
    Message := 'Deleting document failed.';
    TigerLog.WriteLog(etDebug, 'deletedocumentRequest: '+Message);
    AResponse.Contents.Add('<p>' + Message + '</p>');
    AResponse.Code:=500;
    AResponse.CodeText:=Message;
  end;
  Handled := True;
end;

procedure TFPWebobsolete.listRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: boolean);
var
  DocumentArray: TJSONArray;
begin
  AResponse.ContentType := 'application/json';
  DocumentArray := TJSONArray.Create();
  try
    FTigerCore.ListDocuments(INVALIDID, DocumentArray);
    AResponse.Contents.Add(DocumentArray.AsJSON);
  except
    on E: Exception do
    begin
      DocumentArray.Clear;
      DocumentArray.Add(TJSONSTring.Create('listRequest: exception ' + E.Message));
      AResponse.Contents.Insert(0, DocumentArray.AsJSON);
    end;
  end;
  Handled := True;
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
      Success:=FTigerCore.ScanSinglePage(DocumentID);
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

procedure TFPWebobsolete.showdocumentRequest(Sender: TObject;
  ARequest: TRequest; AResponse: TResponse; var Handled: boolean);
// Show pdf given by post with json docid integer
var
  DocumentID: integer;
  InputJSON: TJSONObject;
  Success: boolean;
begin
  Success := False;
  try
    // for uniformity, we expect a POST+a generic json tag, though we could have used e.g. docid directly
    //todo: adapt so InputJSON in URL is also accepted (for gets)
    InputJSON := TJSONParser.Create(ARequest.Content).Parse as TJSONObject;
    DocumentID := InputJSON.Integers['documentid'];
    Success := True;
  except
    TigerLog.WriteLog(etDebug, 'showDocumentRequest: error parsing document id.');
  end;

  if Success then
  begin
    //retrieve pdf and put in output stream
    AResponse.ContentStream := TMemoryStream.Create;
    try
      // Load tiff into content stream:
      if FTigerCore.GetPDF(DocumentID, AResponse.ContentStream) then
      begin
        // Indicate papertiger should be able to deal with this data:
        AResponse.ContentType := 'application/pdf';
        AResponse.ContentLength:=AResponse.ContentStream.Size; //apparently doesn't happen automatically?
        AResponse.SendContent;
      end
      else
      begin
        // Not found? error message
        AResponse.Code:=404;
        AResponse.CodeText:='Error getting PDF file for document ID ' +
          IntToStr(DocumentID);
        AResponse.Contents.Add('<p>Error getting PDF file for document ID ' +
          IntToStr(DocumentID) + '</p>');
      end;
    finally
      AResponse.ContentStream.Free;
    end;
  end
  else
  begin
    // error message
    AResponse.Code:=404;
    AResponse.CodeText:='Error retrieving PDF for document ID ' +
      IntToStr(DocumentID);
    AResponse.Contents.Add('<p>Error retrieving PDF for document ID ' +
      IntToStr(DocumentID) + '</p>');
  end;
  Handled := True;
end;

procedure TFPWebobsolete.showimageRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: boolean);
// Show image given by post with json docid integer
var
  DocumentID, ImageOrder: integer;
  Query: TJSONObject;
  Success: boolean;
begin
  Success := False;
  try
    // for uniformity, we expect a POST+a generic json tag, though we could have used e.g. docid directly
    //todo: adapt so query in URL is also accepted (for gets)
    Query := TJSONParser.Create(ARequest.Content).Parse as TJSONObject;
    DocumentID := Query.Integers['documentid'];
    ImageOrder := Query.Integers['imageorder']; //image order number
    Success := True;
  except
    TigerLog.WriteLog(etDebug, 'showimageRequest: error parsing document id.');
  end;

  if Success then
  begin
    //retrieve tiff and put in output stream
    AResponse.ContentStream := TMemoryStream.Create;
    try
      // Load tiff into content stream:
      if FTigerCore.GetImage(DocumentID, ImageOrder, AResponse.ContentStream) then
      begin
        // Indicate papertiger should be able to deal with this data:
        AResponse.ContentType := 'image/tiff; application=papertiger';
        AResponse.ContentLength:=AResponse.ContentStream.Size; //apparently doesn't happen automatically?
        AResponse.SendContent;
      end
      else
      begin
        // Not found? error message
        AResponse.Code:=404;
        AResponse.CodeText:='Error getting image file for document ID ' +
          IntToStr(DocumentID);
        AResponse.Contents.Add('<p>Error getting image file for document ID ' +
          IntToStr(DocumentID) + '</p>');
      end;
    finally
      AResponse.ContentStream.Free;
    end;
  end
  else
  begin
    // error message
    AResponse.Code:=404;
    AResponse.CodeText:='Error retrieving image for document ID ' +
      IntToStr(DocumentID);
    AResponse.Contents.Add('<p>Error retrieving image for document ID ' +
      IntToStr(DocumentID) + '</p>');
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
  AResponse.Contents.Add('<p>URI: '+ARequest.URI+'</p>'); //gives nothing
  AResponse.Contents.Add('<p>URL: '+ARequest.URL+'</p>'); //gives eg /cgi-bin/tigercgi/unsupported?q=5
  AResponse.Contents.Add('<p>Pathinfo: '+ARequest.PathInfo+'</p>'); //gives /unsupported
  AResponse.Contents.Add('<p>GetNextPathinfo: '+ARequest.GetNextPathInfo+'</p>'); //gives /unsupported
  Handled := True;
end;

procedure TFPWebobsolete.uploadimageRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: boolean);
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
    //todo: actually get document as well
    if DocumentID=INVALIDID then
      raise Exception.Create('Received invalid document ID.');
    //todo: implement image upload
    {if FTigerCore.UploadImage(DocumentID, )='' then
      raise Exception.Create('Error uploading image ument '+inttostr(DocumentID));}
  except
    Message := 'Uploading image failed.';
    TigerLog.WriteLog(etDebug, 'uploadimageRequest: '+Message);
    AResponse.Contents.Add('<p>' + Message + '</p>');
    AResponse.Code:=500;
    AResponse.CodeText:=Message;
  end;
  Handled := True;
end;

initialization
  // This registration will handle http://server/cgi-bin/tigercgi/obsolete/*
  RegisterHTTPModule('obsolete', TFPWebobsolete);
end.
