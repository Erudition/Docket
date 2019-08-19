this.tk = {
    alarmVol: function(a1,a2,a3){return true;},
    audioRecord: function(a1,a2,a3,a4){return true;},
    audioRecordStop: function(){return true;},
    btVoiceVol: function(a1,a2,a3){return true;},
    browseURL: function(a1){return true;},
    button: function(a1){return true;},
    call: function(a1,a2){return true;},
    callBlock: function(a1,a2){return true;},
    callDivert: function(a1,a2,a3){return true;},
    callRevert: function(a1){return true;},
    callVol: function(a1,a2,a3){return true;},
    carMode: function(a1){return true;},
    clearKey: function(a1){return true;},
    composeEmail: function(a1,a2,a3){return true;},
    composeMMS: function(a1,a2,a3,a4){return true;},
    composeSMS: function(a1,a2){return true;},
    convert: function(a1,a2){return ' ';},
    createDir: function(a1,a2,a3){return true;},
    createScene: function(a1){return true;},
    cropImage: function(a1,a2,a3,a4){return true;},
    decryptDir: function(a1,a2,a3){return true;},
    decryptFile: function(a1,a2,a3){return true;},
    deleteDir: function(a1,a2,a3){return true;},
    deleteFile: function(a1,a2,a3){return true;},
    destroyScene: function(a1){return true;},
    disable: function(){return true;},
    displayAutoBright: function(a1){return true;},
    displayAutoRotate: function(a1){return true;},
    displayTimeout: function(a1,a2,a3){return true;},
    dpad: function(a1,a2){return true;},
    dtmfVol: function(a1,a2,a3){return true;},
    elemBackColour: function(a1,a2,a3,a4){return true;},
    elemBorder: function(a1,a2,a3,a4){return true;},
    elemPosition: function(a1,a2,a3,a4,a5,a6){return true;},
    elemText: function(a1,a2,a3,a4){return true;},
    elemTextColour: function(a1,a2,a3){return true;},
    elemTextSize: function(a1,a2,a3){return true;},
    elemVisibility: function(a1,a2,a3,a4){return true;},
    endCall: function(){return true;},
    enableProfile: function(a1,a2){return true;},
    encryptDir: function(a1,a2,a3,a4){return true;},
    encryptFile: function(a1,a2,a3,a4){return true;},
    enterKey: function(a1,a2,a3,a4,a5,a6,a7){return true;},
    exit: function(){console.log("\x1b[31m", "Tasker would have EXIT here.", "\x1b[0m")},
    flash: function(a1){console.log("Tasker would have flashed: \n", "\x1b[33m", a1, "\x1b[0m");},
    flashLong: function(a1){},
    filterImage: function(a1,a2){return true;},
    flipImage: function(a1){return true;},
    getLocation: function(a1,a2,a3){return true;},
    getVoice: function(a1,a2,a3){return ' ';},
    global: function(a1){if(a1=='SDK'||a1=='%SDK'){return '0';}else{return ' ';}},
    goHome: function(a1){},
    haptics: function(a1){return true;},
    hideScene: function(a1){return true;},
    listFiles: function(a1,a2){return ' ';},
    loadApp: function(a1,a2,a3){return true;},
    loadImage: function(a1){return true;},
    local: function(a1){return '';},
    lock: function(a1,a2,a3,a4,a5,a6,a7){return true;},
    mediaControl: function(a1){return true;},
    mediaVol: function(a1,a2,a3){return true;},
    micMute: function(a1){return true;},
    mobileData: function(a1){return true;},
    musicBack: function(a1){return true;},
    musicPlay: function(a1,a2,a3,a4){return true;},
    musicSkip: function(a1){return true;},
    musicStop: function(){return true;},
    nightMode: function(a1){return true;},
    notificationVol: function(a1,a2,a3){return true;},
    performTask: function(a1,a2,a3,a4){return true;},
    popup: function(a1,a2,a3,a4,a5,a6){return true;},
    profileActive: function(a1){return true;},
    pulse: function(a1){return true;},
    readFile: function(a1){return ' ';},
    reboot: function(a1){return true;},
    resizeImage: function(a1,a2){return true;},
    ringerVol: function(a1,a2,a3){return true;},
    rotateImage: function(a1,a2){return true;},
    saveImage: function(a1,a2,a3){return true;},
    say: function(a1,a2,a3,a4,a5,a6,a7,a8){return true;},
    scanCard: function(a1){return true;},
    sendIntent: function(a1,a2,a3,a4,a5,a6,a7,a8){return true;},
    sendSMS: function(a1,a2,a3){return true;},
    setClip: function(a1,a2){return true;},
    settings: function(a1){return true;},
    setAirplaneMode: function(a1){return true;},
    setAirplaneRadios: function(a1){return true;},
    setAlarm: function(a1,a2,a3,a4){return true;},
    setAutoSync: function(a1){return true;},
    setBT: function(a1){return true;},
    setBTID: function(a1){return true;},
    setGlobal: function(a1,a2){},
    setKey: function(a1,a2){return true;},
    setLocal: function(a1,a2){},
    setWallpaper: function(a1){return true;},
    setWifi: function(a1){return true;},
    shell: function(a1,a2,a3){return ' ';},
    showScene: function(a1,a2,a3,a4,a5,a6){return true;},
    shutdown: function(){return true;},
    silentMode: function(a1){return true;},
    sl4a: function(a1,a2){return true;},
    soundEffects: function(a1){return true;},
    speakerphone: function(a1){return true;},
    statusBar: function(a1){return true;},
    stayOn: function(a1){return true;},
    stopLocation: function(a1){return true;},
    systemLock: function(){return true;},
    systemVol: function(a1,a2,a3){return true;},
    takeCall: function(){return true;},
    takePhoto: function(a1,a2,a3,a4){return true;},
    taskRunning: function(a1){return true;},
    type: function(a1,a2){return true;},
    unzip: function(a1,a2){return true;},
    usbTether: function(a1){return true;},
    vibrate: function(a1){},
    vibratePattern: function(a1){return true;},
    wait: function(a1){return true;},
    wifiTether: function(a1){return true;},
    writeFile: function(a1,a2,a3){return true;},
    zip: function(a1,a2,a3){return true;},
}
// v1 tv5.6