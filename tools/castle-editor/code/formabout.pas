unit FormAbout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Buttons;

type
  TAboutForm = class(TForm)
    BitBtn1: TBitBtn;
    ImageLogo: TImage;
    LabelWebsite: TLabel;
    LabelName: TLabel;
    LabelVersion: TLabel;
    LabelCopyright: TLabel;
    LabelWebsite1: TLabel;
    procedure BitBtn1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure LabelWebsite1Click(Sender: TObject);
    procedure LabelWebsiteClick(Sender: TObject);
  private

  public

  end;

var
  AboutForm: TAboutForm;

implementation

uses CastleOpenDocument, CastleUtils;

{$R *.lfm}

// TODO: Show current (runtime) CGE, FPC version
// TODO: Show CGE, FPC version when compiling editor

procedure TAboutForm.LabelWebsiteClick(Sender: TObject);
begin
  OpenURL('https://castle-engine.io/');
end;

procedure TAboutForm.LabelWebsite1Click(Sender: TObject);
begin
  OpenURL('https://patreon.com/castleengine/');
end;

procedure TAboutForm.BitBtn1Click(Sender: TObject);
begin
  Close;
end;

procedure TAboutForm.FormCreate(Sender: TObject);
begin
  LabelVersion.Caption := 'Version: ' + CastleEngineVersion;
end;

end.

