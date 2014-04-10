unit tigercgi_image;

{ Papertiger CGI handling for image-related functionality.

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

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, httpdefs, fpHTTP, fpWeb, tigerutil, tigerservercore,
  strutils, fpjson, jsonparser;

type

  { TFPWebimage }

  TFPWebimage = class(TFPWebModule)
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
    procedure DataModuleRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: boolean);
  private
    { private declarations }
    FTigerCore: TTigerServerCore;
  public
    { public declarations }
  end;

var
  FPWebimage: TFPWebimage;

implementation

{$R *.lfm}

{ TFPWebimage }

procedure TFPWebimage.DataModuleCreate(Sender: TObject);
begin
  FTigerCore := TTigerServerCore.Create;
end;

procedure TFPWebimage.DataModuleDestroy(Sender: TObject);
begin
  FTigerCore.Free;
end;

procedure TFPWebimage.DataModuleRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: boolean);
// We don't define any actions but handle the request at the module level before any actions would be evaluated.
{
Handled URLs/methods:
DELETE http://server/cgi-bin/tigercgi/image/               //delete all images?!?!
GET    http://server/cgi-bin/tigercgi/image/               //list of images
GET    http://server/cgi-bin/tigercgi/image/ with documentid, imageorder in JSON: get imageID of requested image
POST   http://server/cgi-bin/tigercgi/image?documentid=55  // let server scan new image, return imageid
POST   http://server/cgi-bin/tigercgi/image?documentid=55  // with image posted as form data: upload image, return imageid
DELETE http://server/cgi-bin/tigercgi/image/304            //remove image with id 304
GET    http://server/cgi-bin/tigercgi/image/304            //get image with id 304
PUT    http://server/cgi-bin/tigercgi/image/304            //edit image with id 304
}
var
  ContentStream: TStringStream;
  DocumentID: integer;
  ImageArray: TJSONArray;
  ImageID: integer;
  ImageOrder: integer;
  InputJSON: TJSONObject;
  IsValidRequest: boolean;
  OutputJSON: TJSONObject;
  StrippedPath: string; // e.g. http://server/cgi-bin/tigercgi/image/123 becomes image/123
  Parser: TJSONParser;
begin
  IsValidRequest := False;
  {
  pathinfo apparently returns something like
  /image/304
  StrippedPath will remove trailing and leading /
  }
  StrippedPath := copy(ARequest.PathInfo, 2, Length(ARequest.PathInfo));
  if RightStr(StrippedPath, 1) = '/' then
    StrippedPath := Copy(StrippedPath, 1, Length(StrippedPath) - 1);
  TigerLog.WriteLog(etDebug, 'Image module: got stripped path: ' +
    StrippedPath + ' with method ' + ARequest.Method);
  if ARequest.QueryString <> '' then
    TigerLog.WriteLog(etDebug, 'Image module: got query: ' + ARequest.QueryString);
  TigerLog.WriteLog(etDebug, 'StrippedPath wordcount: ' + IntToStr(WordCount(StrippedPath, ['/'])));

  // Make sure the user didn't specify levels in the URI we don't support:
  case ARequest.Method of
    'DELETE':
    begin
      case WordCount(StrippedPath, ['/']) of
        1: //http://server/cgi-bin/tigercgi/image/
        // Note that this is a bit of a ridiculous call: deleting images without deleting the documents/pdfs
        begin
          IsValidRequest := FTigerCore.DeleteImages(true);
        end;
        2: //http://server/cgi-bin/tigercgi/image/304
        begin
          ImageID := StrToIntDef(ExtractWord(2, StrippedPath, ['/']), INVALIDID);
          if ImageID = INVALIDID then
            IsValidRequest := false
          else
            IsValidRequest := FTigerCore.DeleteImage(ImageID,true);
        end;
      end;
    end;
    'GET':
    begin
      case WordCount(StrippedPath, ['/']) of
        1: //http://server/cgi-bin/tigercgi/image/ get:
        // - list of images
        // - a specific imageID based on document id, imageorder
        if (ARequest.ContentType='application/json') and
          (ARequest.Content<>'') then
        // Specific image (imageorder is optional; take first one if missing
        //{ "documentid" : 2103354, "imageorder" : 1 }
        begin
          ContentStream := TStringStream.Create(ARequest.Content);
          Parser := TJSONParser.Create(ContentStream);
          try
            try
              InputJSON := TJSONObject(Parser.Parse);
              if (InputJSON.Find('documentid',jtNumber)<>nil) then
                DocumentID := InputJSON.Integers['documentid'];
              if (InputJSON.Find('imageorder',jtNumber)<>nil) then
                ImageOrder := InputJSON.Integers['imageorder']
              else //take first one - or perhaps should have taken all using invalidid?
                ImageOrder := 1;
              IsValidRequest := true;
              ImageArray := TJSONArray.Create();
              try
                FTigerCore.ListImages(DocumentID, ImageOrder, ImageArray);
                //todo: debug
                Tigerlog.writelog('image get debug: got document id: '+inttostr(documentid));
                Tigerlog.writelog('image get debug: got imageorder id: '+inttostr(imageorder));
                Tigerlog.writelog('image get debug: got imagearray: '+ImageArray.AsJSON);
                AResponse.ContentType := 'application/json';
                AResponse.Contents.Add(ImageArray.AsJSON);
              except
                on E: Exception do
                begin
                  ImageArray.Clear;
                  ImageArray.Add(TJSONSTring.Create('listRequest: exception ' +
                    E.Message));
                  AResponse.Contents.Insert(0, ImageArray.AsJSON);
                end;
              end;
            except
              // error occurred, e.g. we have regular HTML instead of JSON
              on E: Exception do
              begin
                TigerLog.WriteLog('Image get: got JSON: '+ARequest.Content+' but error parsing/processing: '+E.Message);
                IsValidRequest:=false;
              end;
            end;
          finally
            Parser.Free;
            ContentStream.Free;
            InputJSON.Free;
          end;
        end
        else
        begin
          // No JSON data in request; assume list of all images
          IsValidRequest := True;
          DocumentID:=InvalidID;
          ImageArray := TJSONArray.Create();
          try
            FTigerCore.ListImages(DocumentID, InvalidID, ImageArray);
            AResponse.ContentType := 'application/json';
            AResponse.Contents.Add(ImageArray.AsJSON);
          except
            on E: Exception do
            begin
              ImageArray.Clear;
              ImageArray.Add(TJSONSTring.Create('listRequest: exception ' +
                E.Message));
              AResponse.Contents.Insert(0, ImageArray.AsJSON);
            end;
          end;
        end;

        // Still 'GET':
        2: //http://server/cgi-bin/tigercgi/image/304 get specific image
        begin
          //todo: debug
          tigerlog.writelog('image get: first word is '+lowercase(extractword(1,strippedpath,['/'])));
          if lowercase(ExtractWord(1, StrippedPath, ['/'])) = 'image' then
          begin
            ImageID := StrToIntDef(ExtractWord(2, StrippedPath, ['/']), INVALIDID);
            //todo: debug
            tigerlog.writelog('image get: client is asking for image '+extractword(2,strippedpath,['/']));
            if ImageID <> INVALIDID then
            begin
              IsValidRequest := True;
              //retrieve tiff and put in output stream
              AResponse.ContentStream := TMemoryStream.Create;
              try
                // Load tiff into content stream:
                //todo: replace this with image id => then add a call getimageid from document input documentid, order output imageid
                if FTigerCore.GetImage(DocumentID, 1, AResponse.ContentStream) then
                begin
                  // Indicate papertiger should be able to deal with this data:
                  AResponse.ContentType := 'image/tiff; application=papertiger';
                  AResponse.ContentLength := AResponse.ContentStream.Size;
                  //apparently doesn't happen automatically?
                  AResponse.SendContent;
                end
                else
                begin
                  ISValidRequest := False; //ask follow up code to return 404 error
                end;
              finally
                AResponse.ContentStream.Free;
              end;
            end;
          end;
        end;
      end;
    end;
    'POST':
    begin
      {
      POST   http://server/cgi-bin/tigercgi/image?documentid=55 // let server scan new image, return imageid
      POST   http://server/cgi-bin/tigercgi/image?documentid=55 // with image posted as form data: upload image, return imageid
      }
      // Note we don't allow empty images to be created: either scan or upload image
      if WordCount(StrippedPath, ['/']) = 1 then
      begin
        // Check if user wants to add image/scan to existing document, by a query field or...
        DocumentID := INVALIDID;
        if (ARequest.QueryFields.Values['documentid'] <> '') then
        begin
          DocumentID := StrToIntDef(ARequest.QueryFields.Values['documentid'], INVALIDID);
          if DocumentID <> INVALIDID then
          begin
            // Check for uploaded image file
            if ARequest.Files.Count > 0 then
            begin
              ImageID := FTigerCore.AddImage(ARequest.Files[0].Stream,
                ARequest.Files[0].FileName, DocumentID, -1);
              if ImageID <> INVALIDID then
                IsValidRequest := True
              else
                TigerLog.WriteLog(etDebug,'Module image: upload image attempt resulted in error.');
            end
            else
            begin
              // Scan.
              TigerLog.WriteLog(etDebug,'Module image: going to start scan for document id '+inttostr(DocumentID));
              // todo: add support for uploading image
              ImageID := FTigerCore.ScanSinglePage(DocumentID);
              if ImageID <> INVALIDID then
              begin
                IsValidRequest := True;
                AResponse.ContentType := 'application/json';
                OutputJSON := TJSONObject.Create();
                try
                  OutputJSON.Add('imageid', ImageID);
                  AResponse.Contents.Add(OutputJSON.AsJSON);
                finally
                  OutputJSON.Free;
                end;
              end
              else
              begin
                TigerLog.WriteLog(etDebug,'Module image: error calling ScanSinglePage for document '+inttostr(DocumentID));
                IsValidRequest := False; //for extra clarity, not really needed
              end;
            end;
          end
          else
          begin
            TigerLog.WriteLog(etDebug,'Module image: POST handler: received no document ID in query field.');
          end;
        end;
      end;
      // Still in POST...
      if IsValidRequest then
      begin
        AResponse.ContentType := 'application/json';
        OutputJSON := TJSONObject.Create();
        try
          OutputJSON.Add('imageid', ImageID);
          AResponse.Contents.Add(OutputJSON.AsJSON);
        finally
          OutputJSON.Free;
        end;
      end;
    end;
    'PUT':
    begin
      //http://server/cgi-bin/tigercgi/image/304 modify this image/replace with new data
      if WordCount(StrippedPath, ['/']) = 2 then
      begin
        ImageID := StrToIntDef(ExtractWord(2, StrippedPath, ['/']), INVALIDID);
        if ImageID <> INVALIDID then
          IsValidRequest := True;
        //todo: modify given image
        AResponse.Contents.Add('<p>todo put/modify image ' + IntToStr(ImageID) + '</p>');
      end;
    end;
  end;
  if not (IsValidRequest) then
  begin
    TigerLog.WriteLog(etWarning, 'Image module: invalid request; got stripped path: ' +
      StrippedPath + ' with method: ' + ARequest.Method);
    if ARequest.QueryString <> '' then
      TigerLog.WriteLog(etWarning, 'Image module: invalid request; got query: ' +
        ARequest.QueryString);
    TigerLog.WriteLog(etDebug,
      'Image module: invalid request; got URL interesting wordcount: ' +
      IntToStr(WordCount(StrippedPath, ['/'])));
    AResponse.Code := 404;
    AResponse.CodeText := 'Image not found.';
    AResponse.Contents.Add('<p>Image not found/invalid request</p>');
  end;
  Handled := True;
end;

initialization
  // This registration will handle http://server/cgi-bin/tigercgi/image/*
  RegisterHTTPModule('image', TFPWebimage);
end.
