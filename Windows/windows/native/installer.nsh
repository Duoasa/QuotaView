!macro customUnInstall
  ${IfNot} ${isUpdated}
    ExecWait '"$INSTDIR\${APP_EXECUTABLE_FILENAME}" --cleanup-integrations' $0
    ${If} $0 != 0
      DetailPrint "Integration cleanup failed. Close QuotaView and disable its connections before retrying."
      IfSilent +2
      MessageBox MB_OK|MB_ICONEXCLAMATION "QuotaView could not disconnect all integrations. Close QuotaView, disable its connections in Settings, and retry uninstall. Your settings and backups have been preserved."
      Abort
    ${EndIf}
  ${EndIf}
!macroend
