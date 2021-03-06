/*
*  ViewController.swift
*  Maccha Browser
*
*  This Source Code Form is subject to the terms of the Mozilla Public
*  License, v. 2.0. If a copy of the MPL was not distributed with this
*  file, You can obtain one at http://mozilla.org/MPL/2.0/.
*
*  Created by Jason Wong on 28/01/2016.
*  Copyright © 2016 Studios Pâtes, Jason Wong (mail: jasonkwh@gmail.com).
*/

import UIKit
import AudioToolbox
import RealmSwift

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate, SWRevealViewControllerDelegate, UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate {
    @IBOutlet weak var mask: UIView!
    @IBOutlet weak var barView: UIView!
    @IBOutlet weak var windowView: UIButton!
    @IBOutlet weak var refreshStopButton: UIButton!
    @IBOutlet weak var urlField: UITextField!
    @IBOutlet weak var backButton: UIBarButtonItem!
    @IBOutlet weak var forwardButton: UIBarButtonItem!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var bar: UIToolbar!
    var moveToolbar: Bool = false
    var moveToolbarShown: Bool = false
    var moveToolbarReturn: Bool = false
    var webAddress: String = ""
    var webTitle: String = ""
    var scrollDirectionDetermined: Bool = false
    var scrollMakeStatusBarDown: Bool = false
    var google: String = "https://www.google.com"
    var tempUrl: String = ""
    var pbString: String = ""
    var touchPoint: CGPoint = CGPointZero
    let imageFormats: String = "\\.jpg$|\\.jpeg$|\\.svg$|\\.png$|\\.gif$|\\.bmp$|\\.tiff$"
    
    //remember previous scrolling position~~
    let panPressRecognizer = UIPanGestureRecognizer()
    var scrollPositionRecord: Bool = false //user tap, record scroll position
    
    //actionsheet
    var longPressRecognizer = UILongPressGestureRecognizer()
    var longPressSwitch: Bool = false
    
    required init?(coder aDecoder: NSCoder) {
        //Inject safari-reader.js, and initialise the wkwebview
        let path_reader = NSBundle.mainBundle().pathForResource("safari-reader", ofType: "js")
        let script = try! String(contentsOfFile: path_reader!, encoding: NSUTF8StringEncoding)
        let userScript = WKUserScript(source: script, injectionTime: .AtDocumentEnd, forMainFrameOnly: false)
        let userContentController = WKUserContentController()
        userContentController.addUserScript(userScript)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        WKWebviewFactory.sharedInstance.webView = WKWebView(frame: CGRectZero, configuration: configuration)
        super.init(coder: aDecoder)
        
        WKWebviewFactory.sharedInstance.webView.navigationDelegate = self
        WKWebviewFactory.sharedInstance.webView.UIDelegate = self
        WKWebviewFactory.sharedInstance.webView.scrollView.delegate = self
        
        //use AFNetworking module to set NSURLCache
        let manager = AFHTTPSessionManager()
        manager.requestSerializer.cachePolicy = NSURLRequestCachePolicy.ReturnCacheDataElseLoad
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        //Splash Screen
        let splashView: CBZSplashView = CBZSplashView(icon: UIImage(named: "Tea"), backgroundColor: UIColor(netHex:0x70BF41))
        self.view.addSubview(splashView)
        splashView.startAnimation()
        
        Reach().monitorReachabilityChanges() //use Reach() module to check network connections
        
        //register observer for willEnterForeground / willEnterBackground state
        //NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationWillEnterForeground:", name: UIApplicationWillEnterForegroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(UIApplicationDelegate.applicationWillEnterForeground(_:)), name: UIApplicationDidBecomeActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ViewController.applicationWillEnterBackground(_:)), name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ViewController.windowUpdate(_:)), name: "updateWindow", object: nil)
        
        self.revealViewController().delegate = self
        if self.revealViewController() != nil {
            revealViewController().rightViewRevealWidth = 240
            self.view.addGestureRecognizer(self.revealViewController().panGestureRecognizer())
        }
        
        mask.backgroundColor = UIColor.blackColor()
        mask.alpha = 0
        view.layer.cornerRadius = 5 //set corner radius of uiview
        view.layer.masksToBounds = true
        
        addToolBar(urlField)
        definesUrlfield() //setup urlfield style
        displayRefreshOrStop() //display refresh or change to stop while loading...
        
        let config = Realm.Configuration(
            // Set the new schema version. This must be greater than the previously used
            // version (if you've never set a schema version before, the version is 0).
            schemaVersion: 1,
            
            // Set the block which will be called automatically when opening a Realm with
            // a schema version lower than the one set above
            migrationBlock: { migration, oldSchemaVersion in
                // We haven’t migrated anything yet, so oldSchemaVersion == 0
                switch oldSchemaVersion {
                case 1:
                    break
                default:
                    // Nothing to do!
                    // Realm will automatically detect new properties and removed properties
                    // And will update the schema on disk automatically
                    self.zeroToOne(migration)
                }
        })
        
        _ = try! Realm(configuration: config) // Invoke migration block if needed
        
        loadRealmData()
        
        if(slideViewValue.newUser == 0) {
            //set original homepage at index 0 of store array
            slideViewValue.windowStoreTitle = ["Google"]
            slideViewValue.windowStoreUrl = [google]
            slideViewValue.scrollPosition = ["0.0"]
            slideViewValue.newUser = 1
        }
        
        //display current window number on the window button
        displayCurWindowNum(slideViewValue.windowStoreTitle.count)
        
        //set toolbar color and style
        bar.clipsToBounds = true
        toolbarColor(slideViewValue.toolbarStyle)
        
        //set Toast alert style
        var style = ToastStyle()
        style.messageColor = UIColor(netHex: 0xECF0F1)
        style.backgroundColor = UIColor(netHex:0x444444)
        ToastManager.shared.style = style
        
        WKWebviewFactory.sharedInstance.webView.snapshotViewAfterScreenUpdates(true) //snapshot webview after loading new screens
        self.navigationController?.navigationBarHidden = true //hide navigation bar
        
        //hook the tap press event
        panPressRecognizer.delegate = self
        panPressRecognizer.addTarget(self, action: #selector(ViewController.onPanPress(_:)))
        WKWebviewFactory.sharedInstance.webView.scrollView.addGestureRecognizer(panPressRecognizer)
        
        //long press to show the action sheet
        longPressRecognizer.delegate = self
        longPressRecognizer.addTarget(self, action: #selector(ViewController.onLongPress(_:)))
        WKWebviewFactory.sharedInstance.webView.scrollView.addGestureRecognizer(longPressRecognizer)
        
        //user agent string
        let ver:String = "Kapiko/4.0 Maccha/" + slideViewValue.version()
        WKWebviewFactory.sharedInstance.webView.performSelector(Selector("_setApplicationNameForUserAgent:"), withObject: ver)
        
        WKWebviewFactory.sharedInstance.webView.allowsBackForwardNavigationGestures = true //enable Back & Forward gestures
        barView.frame = CGRect(x:0, y: 0, width: view.frame.width, height: 30)
        view.insertSubview(WKWebviewFactory.sharedInstance.webView, belowSubview: progressView)
        WKWebviewFactory.sharedInstance.webView.translatesAutoresizingMaskIntoConstraints = false
        let height = NSLayoutConstraint(item: WKWebviewFactory.sharedInstance.webView, attribute: .Height, relatedBy: .Equal, toItem: view, attribute: .Height, multiplier: 1, constant: -44)
        let width = NSLayoutConstraint(item: WKWebviewFactory.sharedInstance.webView, attribute: .Width, relatedBy: .Equal, toItem: view, attribute: .Width, multiplier: 1, constant: 0)
        view.addConstraints([height, width])
        
        WKWebviewFactory.sharedInstance.webView.addObserver(self, forKeyPath: "loading", options: .New, context: nil)
        WKWebviewFactory.sharedInstance.webView.addObserver(self, forKeyPath: "estimatedProgress", options: .New, context: nil)
        
        //Create Handoff instance
        let activity:NSUserActivity = NSUserActivity(activityType: "com.studiospates.maccha.handsoff") //handoff listener
        self.userActivity = activity
        self.userActivity?.becomeCurrent()
        
        backButton.enabled = false
        forwardButton.enabled = false
        
        slideViewValue.scrollPositionSwitch = true
        if(slideViewValue.shortcutItem == 0) {
            if(slideViewValue.newUser == 0) {
                loadRequest(slideViewValue.windowStoreUrl[0])
            } else {
                loadRequest(slideViewValue.windowStoreUrl[slideViewValue.windowCurTab])
            }
        }
        else {
            let pb: UIPasteboard = UIPasteboard.generalPasteboard()
            if(pb.string == nil) {
                pbString = ""
            } else {
                pbString = pb.string!
            }
            if((slideViewValue.shortcutItem == 1) || ((slideViewValue.shortcutItem == 2) && (pbString != "") && (checkConnectionStatus() == true))){
                openShortcutItem()
            }
            if((slideViewValue.shortcutItem == 2) && (pbString == "")) {
                loadRequest(slideViewValue.windowStoreUrl[slideViewValue.windowCurTab])
                slideViewValue.alertPopup(0, message: "Clipboard is empty")
            }
            if((slideViewValue.shortcutItem == 2) && (checkConnectionStatus() == false)) {
                //Popup alert window
                hideKeyboard()
                slideViewValue.alertPopup(0, message: "The Internet connection appears to be offline.")
            }
        }
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    //Realm migration
    func zeroToOne(migration: Migration) {
        migration.enumerate(GlobalData.className()) {
            oldObject, newObject in
            newObject!["toolbarColor"] = slideViewValue.toolbarStyle
        }
    }
    
    //Load data from Realm database
    func loadRealmData() {
        for wdata in realm_maccha.objects(WkData) {
            slideViewValue.windowStoreTitle = wdata.wk_title
            slideViewValue.windowStoreUrl = wdata.wk_url
            slideViewValue.scrollPosition = wdata.wk_scrollPosition
        }
        for gdata in realm_maccha.objects(GlobalData) {
            slideViewValue.searchEngines = gdata.search
            slideViewValue.windowCurTab = gdata.current_tab
            slideViewValue.newUser = gdata.new_user
            slideViewValue.toolbarStyle = gdata.toolbarColor
        }
        for htdata in realm_maccha.objects(HistoryData) {
            slideViewValue.historyTitle = htdata.history_title
            slideViewValue.historyUrl = htdata.history_url
            slideViewValue.historyDate = htdata.history_date
        }
        for bkdata in realm_maccha.objects(BookmarkData) {
            slideViewValue.likesTitle = bkdata.like_title
            slideViewValue.likesUrl = bkdata.like_url
        }
    }
    
    //Determine quick actions...
    func openShortcutItem() {
        //reset readActions
        slideViewValue.readActions = false
        slideViewValue.readRecover = false
        slideViewValue.readActionsCheck = false
        
        windowView.setTitle(String(slideViewValue.windowStoreTitle.count), forState: UIControlState.Normal)
        if(slideViewValue.shortcutItem == 1) {
            slideViewValue.windowCurTab = slideViewValue.windowCurTab + 1
            slideViewValue.windowStoreTitle.insert("", atIndex: slideViewValue.windowCurTab)
            slideViewValue.windowStoreUrl.insert("about:blank", atIndex: slideViewValue.windowCurTab)
            slideViewValue.scrollPosition.insert("0.0", atIndex: slideViewValue.windowCurTab)
            loadRequest("about:blank")
        }
        else if(slideViewValue.shortcutItem == 2) {
            if(slideViewValue.windowStoreUrl[slideViewValue.windowCurTab] != "about:blank") {
                slideViewValue.windowCurTab = slideViewValue.windowCurTab + 1
                slideViewValue.windowStoreTitle.insert("", atIndex: slideViewValue.windowCurTab)
                slideViewValue.windowStoreUrl.insert("about:blank", atIndex: slideViewValue.windowCurTab)
                slideViewValue.scrollPosition.insert("0.0", atIndex: slideViewValue.windowCurTab)
            }
            //Open URL from clipboard
            loadRequest(pbString)
            slideViewValue.windowStoreTitle[slideViewValue.windowCurTab] = WKWebviewFactory.sharedInstance.webView.title!
            slideViewValue.windowStoreUrl[slideViewValue.windowCurTab] = (WKWebviewFactory.sharedInstance.webView.URL?.absoluteString)!
        }
        slideViewValue.shortcutItem = 0
    }
    
    //function to update windows count from another class
    func windowUpdate(notification: NSNotification) {
        windowView.setTitle(String(slideViewValue.windowStoreTitle.count), forState: UIControlState.Normal)
    }
    
    //actions those the app going to do when the app enters foreground
    func applicationWillEnterForeground(notification: NSNotification) {
        let pb: UIPasteboard = UIPasteboard.generalPasteboard()
        if(pb.string == nil) {
            pbString = ""
        } else {
            pbString = pb.string!
        }
        if((slideViewValue.shortcutItem == 1) || ((slideViewValue.shortcutItem == 2) && (pbString != ""))){
            openShortcutItem()
        }
        if((slideViewValue.shortcutItem == 2) && (pbString == "")) {
            slideViewValue.alertPopup(0, message: "Clipboard is empty")
        }
    }
    
    //actions those the app going to do when the app enters background
    func applicationWillEnterBackground(notification: NSNotification) {
        
    }
    
    override func canBecomeFirstResponder() -> Bool {
        return true
    }
    
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func onPanPress(gestureRecognizer:UIGestureRecognizer){
        if gestureRecognizer.state == UIGestureRecognizerState.Began {
            scrollPositionRecord = true
        }
        if gestureRecognizer.state == UIGestureRecognizerState.Ended {
            scrollPositionRecord = false
        }
    }
    
    func onLongPress(gestureRecognizer:UIGestureRecognizer){
        touchPoint = gestureRecognizer.locationInView(self.view)
        //disable the original wkactionsheet
        WKWebviewFactory.sharedInstance.webView.evaluateJavaScript("document.body.style.webkitTouchCallout='none';", completionHandler: nil)
        longPressSwitch = true
    }

    //function to hide the statusbar
    func hideStatusbar() {
        UIApplication.sharedApplication().setStatusBarHidden(true, withAnimation: UIStatusBarAnimation.Slide)
    }
    
    //function to show the statusbar
    func showStatusbar() {
        UIApplication.sharedApplication().setStatusBarHidden(false, withAnimation: UIStatusBarAnimation.Slide)
    }
    
    //detect the right reveal view is toggle, and do some actions...
    func revealController(revealController: SWRevealViewController!, willMoveToPosition position: FrontViewPosition) {
        if revealController.frontViewPosition == FrontViewPosition.Left
        {
            hideKeyboard()
            hideStatusbar()
            WKWebviewFactory.sharedInstance.webView.userInteractionEnabled = false
            self.bar.userInteractionEnabled = false
            UIView.animateWithDuration(0.2, delay: 0.0, options: UIViewAnimationOptions.CurveEaseOut, animations: {
                self.mask.alpha = 0.6
                }, completion: { finished in
            })
        }
        else
        {
            windowView.setTitle(String(slideViewValue.windowStoreTitle.count), forState: UIControlState.Normal)
            self.presentingViewController?.dismissViewControllerAnimated(true, completion: nil)
            WKWebviewFactory.sharedInstance.webView.userInteractionEnabled = true
            self.bar.userInteractionEnabled = true
            UIView.animateWithDuration(0.2, delay: 0.0, options: UIViewAnimationOptions.CurveEaseIn, animations: {
                self.mask.alpha = 0
                }, completion: { finished in
            })
            if((slideViewValue.readActions == true) && (slideViewValue.readRecover == false)) {
                if(slideViewValue.readActionsCheck == false) {
                    tempUrl = webAddress //tempUrl updates only once...
                }
                WKWebviewFactory.sharedInstance.webView.evaluateJavaScript("var ReaderArticleFinderJS = new ReaderArticleFinder(document);") { (obj, error) -> Void in
                }
                WKWebviewFactory.sharedInstance.webView.evaluateJavaScript("var article = ReaderArticleFinderJS.findArticle();") { (html, error) -> Void in
                }
                WKWebviewFactory.sharedInstance.webView.evaluateJavaScript("article.element.innerText") { (res, error) -> Void in
                    //if let html = res as? String {
                        //self.webView.loadHTMLString(html, baseURL: nil)
                    //}
                }
                WKWebviewFactory.sharedInstance.webView.evaluateJavaScript("article.element.outerHTML") { (res, error) -> Void in
                    if let html = res as? String {
                        if(slideViewValue.readActionsCheck == false) {
                            WKWebviewFactory.sharedInstance.webView.loadHTMLString("<body style='font-family: -apple-system; font-family: '-apple-system','HelveticaNeue';'><meta name = 'viewport' content = 'user-scalable=no, width=device-width'>" + html, baseURL: nil)
                        }
                    }
                }
                WKWebviewFactory.sharedInstance.webView.evaluateJavaScript("ReaderArticleFinderJS.isReaderModeAvailable();") { (html, error) -> Void in
                    if(String(html) == "Optional(0)") {
                        if(slideViewValue.readActionsCheck == false) {
                            //this avoids alert popups while hiding the slideViewController (although the user did not press the read button)
                            slideViewValue.alertPopup(0, message: "Reader mode is not available for this page")
                            slideViewValue.readActions = false //disable readbility
                        }
                    }
                    else {
                        slideViewValue.readActionsCheck = true //turns on the boolean switch on to avoid alert popups
                    }
                }
                WKWebviewFactory.sharedInstance.webView.evaluateJavaScript("ReaderArticleFinderJS.prepareToTransitionToReader();") { (html, error) -> Void in
                }
            }
            if((slideViewValue.readActions == true) && (slideViewValue.readRecover == true)) {
                //load contents by wkwebview
                loadRequest(tempUrl)
                slideViewValue.readActionsCheck = false //reset
                slideViewValue.readRecover = false
            }
        }
    }
    
    //scroll down to hide status bar, scroll up to show status bar, with animations
    func scrollViewDidScroll(scrollView: UIScrollView) {
        //store current scroll positions to array
        if(scrollPositionRecord == true) {
            slideViewValue.scrollPosition[slideViewValue.windowCurTab] = scrollView.contentOffset.y.description
        }
        
        if !scrollDirectionDetermined {
            if(moveToolbar == false) {
                let translation = scrollView.panGestureRecognizer.translationInView(self.view)
                if translation.y > 0 {
                    showStatusbar()
                    scrollDirectionDetermined = true
                    scrollMakeStatusBarDown = true
                }
                else if translation.y < 0 {
                    hideStatusbar()
                    scrollDirectionDetermined = true
                    scrollMakeStatusBarDown = false
                }
            }
        }
    }
    
    func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        scrollDirectionDetermined = false
    }
    
    func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        scrollDirectionDetermined = false
    }
    
    override func canResignFirstResponder() -> Bool {
        return true
    }
    
    //shake to change toolbar color, phone will vibrate for confirmation
    override func motionEnded(motion: UIEventSubtype, withEvent event: UIEvent?) {
        let matches = matchesForRegexInText("iPad", text: UIDevice.currentDevice().modelName) //check iPad?
        if (motion == .MotionShake) && (matches == []) {
            if(slideViewValue.toolbarStyle < 2) {
                slideViewValue.toolbarStyle += 1
            }
            else {
                slideViewValue.toolbarStyle = 0
            }
            toolbarColor(slideViewValue.toolbarStyle)
            NSNotificationCenter.defaultCenter().postNotificationName("windowViewReload", object: nil)
            //refreshPressed()
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
    
    //function of setting toolbar color
    func toolbarColor(colorID: Int) {
        switch colorID {
        case 0:
            //Green
            progressView.tintColor = UIColor(netHex:0x00882B)
            urlField.backgroundColor = UIColor(netHex:0x00882B)
            bar.barTintColor = UIColor(netHex:0x70BF41)
            slideViewValue.windowCurColour = UIColor(netHex:0x70BF41)
        case 1:
            //Blue
            progressView.tintColor = UIColor(netHex:0x0153A4)
            urlField.backgroundColor = UIColor(netHex:0x0153A4)
            bar.barTintColor = UIColor(netHex:0x499AE7)
            slideViewValue.windowCurColour = UIColor(netHex:0x499AE7)
        case 2:
            //Pink, for Sherry my dear
            progressView.tintColor = UIColor(netHex:0xd672ac)
            urlField.backgroundColor = UIColor(netHex:0xd672ac)
            bar.barTintColor = UIColor(netHex:0xea89be)
            slideViewValue.windowCurColour = UIColor(netHex:0xea89be)
        default:
            break
        }
    }
    
    //function which defines the clear button of the urlfield and some characteristics of urlfield
    func definesUrlfield() {
        /** iPads **/
        if(UIScreen.mainScreen().bounds.width == 1024.0) {
            urlField.frame.size.width = UIScreen.mainScreen().bounds.width * 0.21
        }
        if(UIScreen.mainScreen().bounds.width == 768.0) {
            urlField.frame.size.width = UIScreen.mainScreen().bounds.width * 0.28
        }
        
        /** iPhones **/
        if(UIScreen.mainScreen().bounds.width == 414.0) { //for iPhone 6 Plus, iPhone 6s Plus, or iPhone 7 Plus
            urlField.frame.size.width = UIScreen.mainScreen().bounds.width * 0.51
        }
        if(UIScreen.mainScreen().bounds.width == 375.0) { //for iPhone 6, iPhone 6s, or iPhone 7
            urlField.frame.size.width = UIScreen.mainScreen().bounds.width * 0.58
        }
        if(UIScreen.mainScreen().bounds.width == 320.0) { //for iPhone 4s, iPhone 5, iPhone 5s, or iPhone SE
            urlField.frame.size.width = UIScreen.mainScreen().bounds.width * 0.68
        }
        
        urlField.autoresizingMask = UIViewAutoresizing.FlexibleWidth
        urlField.clipsToBounds = true
        let crButton = UIButton(type: UIButtonType.System)
        crButton.setImage(UIImage(named: "Clear"), forState: UIControlState.Normal)
        crButton.addTarget(self, action: #selector(ViewController.clearPressed), forControlEvents: UIControlEvents.TouchUpInside)
        crButton.imageEdgeInsets = UIEdgeInsetsMake(0, -5, 0, 5)
        crButton.frame = CGRectMake(0, 0, 15, 15)
        urlField.rightViewMode = .WhileEditing
        urlField.rightView = crButton
    }
    
    //function to display current window number in the window button
    func displayCurWindowNum(currentNum: Int) {
        windowView.setBackgroundImage(UIImage(named: "Window"), forState: UIControlState.Normal)
        windowView.setTitle(String(currentNum), forState: UIControlState.Normal)
        windowView.addTarget(revealViewController(), action: #selector(SWRevealViewController.rightRevealToggle(_:)), forControlEvents: UIControlEvents.TouchUpInside)
        windowView.frame = CGRectMake(0, 0, 30, 30)
    }
    
    //function to display refresh or change to stop while loading...
    func displayRefreshOrStop() {
        refreshStopButton.setImage(UIImage(named: "Refresh"), forState: UIControlState.Normal)
        refreshStopButton.addTarget(self, action: #selector(ViewController.refreshPressed), forControlEvents: UIControlEvents.TouchUpInside)
        refreshStopButton.imageEdgeInsets = UIEdgeInsetsMake(0, -13, 0, -15)
        refreshStopButton.frame = CGRectMake(0, 0, 30, 30)
    }
    
    //keyboards related
    //show/hide keyboard reactions
    func textFieldDidBeginEditing(textField: UITextField) -> Bool {
        if textField == urlField {
            moveToolbar = true; //move toolbar as the keyboard moves
            
            //display urls in urlfield
            if(moveToolbarShown == false) {
                urlField.textAlignment = .Left
                if(slideViewValue.readActions == true) {
                    urlField.text = tempUrl
                }
                else {
                    if(webAddress != "about:blank") {
                        urlField.text = webAddress
                    } else {
                        urlField.text = ""
                    }
                }
            }
            return true //urlField
        }
        else {
            return false
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.navigationController?.navigationBarHidden = true //hide navigation bar
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        self.navigationController?.navigationBarHidden = true //hide navigation bar
        NSNotificationCenter.defaultCenter().addObserver(self, selector:#selector(ViewController.keyboardWillShow(_:)), name: UIKeyboardWillShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector:#selector(ViewController.keyboardWillHide(_:)), name: UIKeyboardWillHideNotification, object: nil)
    }
    
    //auto show toolbar while editing
    func keyboardWillShow(sender: NSNotification) {
        if(moveToolbar == true) {
            moveToolbarShown = true
            if let userInfo = sender.userInfo {
                if let keyboardHeight = userInfo[UIKeyboardFrameEndUserInfoKey]?.CGRectValue.origin.y {
                    let keyboardHeight2 = userInfo[UIKeyboardFrameEndUserInfoKey]?.CGRectValue.size.height
                    var keyHeight = keyboardHeight-self.view.frame.size.height
                    if(((keyboardHeight-self.view.frame.size.height) > (-keyboardHeight2!)) && ((UIDevice.currentDevice().modelName.containsString("iPhone")) || (UIDevice.currentDevice().modelName.containsString("iPod")))) {
                        keyHeight = -keyboardHeight2!
                    }
                    self.view.frame.origin.y = keyHeight
                    UIView.animateWithDuration(0.10, animations: { () -> Void in
                        self.view.layoutIfNeeded()
                    })
                }
            }
        }
    }
    
    //auto hide toolbar while editing
    func keyboardWillHide(sender: NSNotification) {
        if(moveToolbar == true) {
            self.view.frame.origin.y = 0
            UIView.animateWithDuration(0.10, animations: { () -> Void in self.view.layoutIfNeeded() })
            moveToolbar = false
            moveToolbarShown = false
            if(moveToolbarReturn == false) {
                urlField.textAlignment = .Center
                if(slideViewValue.readActions == true) {
                    urlField.text = "Reader mode"
                } else {
                    urlField.text = webTitle
                }
            }
        }
    }
    
    //function to detect screen orientation change and do some actions
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        barView.frame = CGRect(x: 0, y: 0, width: size.width, height: 30)
        if(scrollMakeStatusBarDown == true) {
            showStatusbar()
        }
        hideKeyboard()
    }
    
    //function to define the actions of urlField.go
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        moveToolbarReturn = true
        urlField.resignFirstResponder()
        
        loadRequest(urlField.text!)
        slideViewValue.readActionsCheck = false
        
        return false
    }
    
    //function to load webview request
    func loadRequest(inputUrlAddress: String) {
        
        if(inputUrlAddress == "about:blank") {
            WKWebviewFactory.sharedInstance.webView.loadRequest(NSURLRequest(URL:NSURL(string: "about:blank")!))
        } else {
            if (checkConnectionStatus() == true) {
                //reset readActions
                slideViewValue.readActions = false
                slideViewValue.readRecover = false
                slideViewValue.readActionsCheck = false
                
                //shorten the url by replacing http and https to null
                let shorten_url = inputUrlAddress.stringByReplacingOccurrencesOfString("https://", withString: "").stringByReplacingOccurrencesOfString("http://", withString: "").stringByReplacingOccurrencesOfString(" ", withString: "+")
                
                //check if it is URL, else use search engine
                var contents: String = ""
                let matches = matchesForRegexInText("(?i)(?:(?:https?):\\/\\/)?(?:\\S+(?::\\S*)?@)?(?:(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}(?:\\.(?:[1-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))|(?:(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)(?:\\.(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)*(?:\\.(?:[a-z\\u00a1-\\uffff]{2,})))(?::\\d{2,5})?(?:\\/[^\\s]*)?", text: ("http://" + shorten_url))
                if(matches == []) {
                    if(slideViewValue.searchEngines == 0) {
                        contents = "http://www.google.com/search?q=" + shorten_url.stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet())!
                    }
                    else if(slideViewValue.searchEngines == 1) {
                        contents = "http://www.bing.com/search?q=" + shorten_url.stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet())!
                    }
                }
                else {
                    contents = "http://" + shorten_url
                }
                
                //load contents by wkwebview
                WKWebviewFactory.sharedInstance.webView.loadRequest(NSURLRequest(URL: NSURL(string: contents)!, cachePolicy: NSURLRequestCachePolicy.ReturnCacheDataElseLoad, timeoutInterval: 15))
            }
            else {
                //Popup alert window
                hideKeyboard()
                slideViewValue.alertPopup(0, message: "The Internet connection appears to be offline.")
                
                //insert a blank page if there's nothing store in the arrays
                if(slideViewValue.windowStoreTitle.count == 0) {
                    slideViewValue.windowStoreTitle.append("")
                    slideViewValue.windowStoreUrl.append("about:blank")
                    
                    //initial y point
                    slideViewValue.scrollPosition.append("0.0")
                }
            }
        }
    }
    
    //function to check current network status, powered by Reach() module
    func checkConnectionStatus() -> Bool {
        switch Reach().connectionStatus() {
        case .Unknown, .Offline:
            return false
        case .Online(.WWAN):
            return true
        case .Online(.WiFi):
            return true
        }
    }
    
    //function to check url by regex
    func matchesForRegexInText(regex: String!, text: String!) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex, options: [])
            let nsString = text as NSString
            let results = regex.matchesInString(text,
                options: [], range: NSMakeRange(0, nsString.length))
            return results.map { nsString.substringWithRange($0.range)}
        } catch let error as NSError {
            print("invalid regex: \(error.localizedDescription)")
            return []
        }
    }
    
    @IBAction func back(sender: UIBarButtonItem) {
        WKWebviewFactory.sharedInstance.webView.goBack()
    }
    
    @IBAction func forward(sender: UIBarButtonItem) {
        WKWebviewFactory.sharedInstance.webView.goForward()
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<()>) {
        if (keyPath == "loading") {
            backButton.enabled = WKWebviewFactory.sharedInstance.webView.canGoBack
            forwardButton.enabled = WKWebviewFactory.sharedInstance.webView.canGoForward
        }
        if (keyPath == "estimatedProgress") {
            progressView.hidden = WKWebviewFactory.sharedInstance.webView.estimatedProgress == 1
            progressView.setProgress(Float(WKWebviewFactory.sharedInstance.webView.estimatedProgress), animated: true)
            
            if(Float(WKWebviewFactory.sharedInstance.webView.estimatedProgress) > 0.0) {
                //set refreshStopButton to stop state
                refreshStopButton.setImage(UIImage(named: "Stop"), forState: UIControlState.Normal)
                refreshStopButton.addTarget(self, action: #selector(ViewController.stopPressed), forControlEvents: UIControlEvents.TouchUpInside)
                
                //display current window numbers
                windowView.setTitle(String(slideViewValue.windowStoreTitle.count), forState: UIControlState.Normal)
            }
            if(Float(WKWebviewFactory.sharedInstance.webView.estimatedProgress) > 0.1) {
                //shorten url by replacing http:// and https:// to null
                let shorten_url = WKWebviewFactory.sharedInstance.webView.URL?.absoluteString!.stringByReplacingOccurrencesOfString("https://", withString: "").stringByReplacingOccurrencesOfString("http://", withString: "")

                //change urlField when the page starts loading
                //display website title in the url field
                webTitle = WKWebviewFactory.sharedInstance.webView.title! //store title into webTitle for efficient use
                webAddress = shorten_url! //store address into webAddress for efficient use
                if(moveToolbar == false) {
                    urlField.textAlignment = .Center
                    if(slideViewValue.readActions == true) {
                        urlField.text = "Reader mode"
                    } else {
                        urlField.text = webTitle
                    }
                }
                moveToolbarReturn = false
                
                //update current window store title and url
                if(slideViewValue.readActions == false) {
                    slideViewValue.windowStoreTitle[slideViewValue.windowCurTab] = WKWebviewFactory.sharedInstance.webView.title!
                    slideViewValue.windowStoreUrl[slideViewValue.windowCurTab] = (WKWebviewFactory.sharedInstance.webView.URL?.absoluteString)!
                }
            }
            if(Float(WKWebviewFactory.sharedInstance.webView.estimatedProgress) == 1.0) {
                //set refresh button style
                refreshStopButton.setImage(UIImage(named: "Refresh"), forState: UIControlState.Normal)
                refreshStopButton.addTarget(self, action: #selector(ViewController.refreshPressed), forControlEvents: UIControlEvents.TouchUpInside)
                
                //Store value for History feature
                if webAddress != "about:blank" {
                    if (slideViewValue.historyUrl.count == 0) { //while history is empty...
                        slideViewValue.historyTitle.append(webTitle)
                        slideViewValue.historyUrl.append((WKWebviewFactory.sharedInstance.webView.URL?.absoluteString)!)
                        slideViewValue.historyDate.append(getCurrentDate())
                    }
                    if (slideViewValue.historyUrl.count > 0) { //while history has entries...
                        //check if this address was exist or not, if yes, delete then append the new, else, append.
                        if slideViewValue.historyUrl.contains((WKWebviewFactory.sharedInstance.webView.URL?.absoluteString)!) {
                            let i = slideViewValue.historyUrl.indexOf((WKWebviewFactory.sharedInstance.webView.URL?.absoluteString)!)
                            slideViewValue.historyUrl.removeAtIndex(i!)
                            slideViewValue.historyUrl.append((WKWebviewFactory.sharedInstance.webView.URL?.absoluteString)!)
                            slideViewValue.historyTitle.removeAtIndex(i!)
                            slideViewValue.historyTitle.append(webTitle)
                            slideViewValue.historyDate.removeAtIndex(i!)
                            slideViewValue.historyDate.append(getCurrentDate())
                        } else {
                            slideViewValue.historyTitle.append(webTitle)
                            slideViewValue.historyUrl.append((WKWebviewFactory.sharedInstance.webView.URL?.absoluteString)!)
                            slideViewValue.historyDate.append(getCurrentDate())
                        }
                    }
                }
            }
        }
    }
    
    func getCurrentDate() -> String {
        //get system date
        let date = NSDate()
        
        //date formatter
        let formatter = NSDateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.stringFromDate(date)
    }
    
    func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: NSError) {
        if (error.code != NSURLErrorCancelled) {
            //Popup alert window
            hideKeyboard()
            slideViewValue.alertPopup(0, message: error.localizedDescription)
            if (error.code == NSURLErrorTimedOut) {
                slideViewValue.scrollPositionSwitch = false //set don't scroll
                loadRequest("about:blank")
            }
        }
    }
    
    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        //disable the original wkactionsheet
        webView.evaluateJavaScript("document.body.style.webkitTouchCallout='none';", completionHandler: nil)
        if(slideViewValue.scrollPositionSwitch == true) {
            WKWebviewFactory.sharedInstance.webView.scrollView.setContentOffset(CGPointMake(0.0, CGFloat(NSNumberFormatter().numberFromString(slideViewValue.scrollPosition[slideViewValue.windowCurTab])!)), animated: true)
            slideViewValue.scrollPositionSwitch = false
        }
        progressView.setProgress(0.0, animated: false)
        updateLikes()
        NSNotificationCenter.defaultCenter().postNotificationName("windowViewReload", object: nil)
        updateUserActivityState(self.userActivity!) //update userActivity
    }
    
    //function to update Handoff userActivity
    override func updateUserActivityState(activity: NSUserActivity) {
        if(WKWebviewFactory.sharedInstance.webView.URL?.absoluteString != "about:blank") {
            activity.webpageURL = WKWebviewFactory.sharedInstance.webView.URL
        }
        super.updateUserActivityState(activity)
    }
    
    func webView(webView: WKWebView, didCommitNavigation navigation: WKNavigation!) {
        WKWebviewFactory.sharedInstance.webView.scrollView.setContentOffset(CGPointZero, animated: false)
    }
    
    // this handles target=_blank links by opening them in the same view
    func webView(webView: WKWebView, createWebViewWithConfiguration configuration: WKWebViewConfiguration, forNavigationAction navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            loadRequest((navigationAction.request.URL?.absoluteString)!)
        }
        return nil
    }
    
    func webView(webView: WKWebView, decidePolicyForNavigationAction navigationAction: WKNavigationAction, decisionHandler: (WKNavigationActionPolicy) -> Void) {
        let url: NSURL = navigationAction.request.URL!
        let urlString: String = url.absoluteString!
        var checkImage: Bool = false
        if (matchesForRegexInText("\\/\\/itunes\\.apple\\.com\\/", text: urlString) != []) {
            UIApplication.sharedApplication().openURL(url)
            decisionHandler(.Cancel)
            return;
        }
        else {
            if navigationAction.navigationType == .LinkActivated && longPressSwitch == true {
                if(matchesForRegexInText(imageFormats, text: urlString) == []) {
                    checkImage = false
                } else {
                    checkImage = true
                }
                self.actionMenu(self, urlStr: urlString, imageCheck: checkImage)
                decisionHandler(.Cancel)
                longPressSwitch = false
                checkImage = false
                return
            }
            if navigationAction.navigationType == .BackForward || navigationAction.navigationType == .LinkActivated {
                //handles the actions when the webview instance is backward or forward
                //reset readActions
                slideViewValue.readActions = false
                slideViewValue.readRecover = false
                slideViewValue.readActionsCheck = false
                hideKeyboard()
            }
        }
        decisionHandler(.Allow)
    }

    //Rebuild Wkactionsheet
    func actionMenu(sender: UIViewController, urlStr: String, imageCheck: Bool) {
        let alertController = UIAlertController(title: "", message: urlStr, preferredStyle: .ActionSheet)
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel) { (action) in
            
        }
        alertController.addAction(cancelAction)
        /*let openAction = UIAlertAction(title: "Open", style: .Default) { (action) in
            //reset readActions
            slideViewValue.readActions = false
            slideViewValue.readRecover = false
            slideViewValue.readActionsCheck = false
            
            self.loadRequest(urlStr)
        }
        alertController.addAction(openAction)*/
        let opentabAction = UIAlertAction(title: "Open In New Tab", style: .Default) { (action) in
            slideViewValue.windowCurTab = slideViewValue.windowCurTab + 1
            slideViewValue.windowStoreTitle.insert(urlStr, atIndex: slideViewValue.windowCurTab)
            slideViewValue.windowStoreUrl.insert(urlStr, atIndex: slideViewValue.windowCurTab)
            slideViewValue.scrollPosition.insert("0.0", atIndex: slideViewValue.windowCurTab)
            
            //update windows count
            self.windowView.setTitle(String(slideViewValue.windowStoreTitle.count), forState: UIControlState.Normal)
            
            //reset readActions
            slideViewValue.readActions = false
            slideViewValue.readRecover = false
            slideViewValue.readActionsCheck = false
            
            self.loadRequest(urlStr)
        }
        alertController.addAction(opentabAction)
        let copyurlAction = UIAlertAction(title: "Copy Link", style: .Default) { (action) in
            let pb: UIPasteboard = UIPasteboard.generalPasteboard();
            pb.string = urlStr
        }
        alertController.addAction(copyurlAction)
        let shareAction = UIAlertAction(title: "Share Link", style: .Default) { (action) in
            let activityViewController = UIActivityViewController(activityItems: [urlStr as NSString], applicationActivities: nil)
            if let vcpopController = activityViewController.popoverPresentationController {
                vcpopController.sourceView = self.view
                vcpopController.sourceRect = CGRectMake(self.touchPoint.x, self.touchPoint.y, 1.0, 1.0)
            }
            if self.presentedViewController == nil {
                self.presentViewController(activityViewController, animated: true, completion: nil)
            }
        }
        alertController.addAction(shareAction)
        var likeAction = UIAlertAction()
        if slideViewValue.likesUrl.contains(urlStr) {
            likeAction = UIAlertAction(title: "Dislike Link", style: .Destructive) { (action) in
                if let i = slideViewValue.likesUrl.indexOf(urlStr) {
                    slideViewValue.likesTitle.removeAtIndex(i)
                    slideViewValue.likesUrl.removeAtIndex(i)
                }
            }
        } else {
            likeAction = UIAlertAction(title: "Like Link", style: .Default) { (action) in
                slideViewValue.likesTitle.append(urlStr)
                slideViewValue.likesUrl.append(urlStr)
            }
        }
        alertController.addAction(likeAction)
        if imageCheck == true {
            let imageAction = UIAlertAction(title: "Save Image", style: .Default) { (action) in
                //Data object to fetch image data
                do {
                    let imageData = try NSData(contentsOfURL: NSURL(string: urlStr)!, options: NSDataReadingOptions())
                    if let webimage = UIImage(data: imageData){
                        UIImageWriteToSavedPhotosAlbum(webimage, nil, nil, nil)
                        slideViewValue.alertPopup(2, message: "Image saved to Camera Roll.") //popup image saved
                    } else {
                        slideViewValue.alertPopup(0, message: "This is not a valid image to download.") //popup warning
                    }
                } catch {
                    print(error)
                }
            }
            alertController.addAction(imageAction)
        }
        
        /* iPad support */
        alertController.popoverPresentationController?.sourceView = self.view
        alertController.popoverPresentationController?.sourceRect = CGRectMake(touchPoint.x, touchPoint.y, 1.0, 1.0)
        
        if self.presentedViewController == nil {
            self.presentViewController(alertController, animated: true, completion: nil)
        }
    }
    
    //function to update titles in bookmarks
    func updateLikes() {
        if(slideViewValue.likesUrl.contains(slideViewValue.windowStoreUrl[slideViewValue.windowCurTab])) {
            slideViewValue.likesTitle[slideViewValue.likesUrl.indexOf(slideViewValue.windowStoreUrl[slideViewValue.windowCurTab])!] = slideViewValue.windowStoreTitle[slideViewValue.windowCurTab]
        } //update corresponding likes title to current tab title
    }
    
    //function to refresh
    func refreshPressed() {
        if(slideViewValue.readActions == false) {
            loadRequest(slideViewValue.windowStoreUrl[slideViewValue.windowCurTab])
        }
        else if(slideViewValue.readActions == true) {
            loadRequest(tempUrl) //load contents by wkwebview
        }
        slideViewValue.scrollPositionSwitch = false
        slideViewValue.readActionsCheck = false
    }
    
    //function to stop page loading
    func stopPressed() {
        if WKWebviewFactory.sharedInstance.webView.loading {
            WKWebviewFactory.sharedInstance.webView.stopLoading()
        }
    }
    
    //function to clear urlfield
    func clearPressed(){
        urlField.text = ""
    }
    
    //function to copy text
    func copyPressed() {
        let pb: UIPasteboard = UIPasteboard.generalPasteboard();
        pb.string = urlField.text
    }
    
    //function to cut text
    func cutPressed() {
        let pb: UIPasteboard = UIPasteboard.generalPasteboard();
        pb.string = urlField.text
        urlField.text = ""
    }
    
    //function to paste text
    func pastePressed() {
        let pb: UIPasteboard = UIPasteboard.generalPasteboard();
        urlField.text = pb.string
    }
    
    //fill webView by 1Password Extension
    func pwPressed(sender: AnyObject) {
        hideKeyboard()
        OnePasswordExtension.sharedExtension().fillItemIntoWebView(WKWebviewFactory.sharedInstance.webView, forViewController: self, sender: sender, showOnlyLogins: false) { (success, error) -> Void in
            if success == false {
                slideViewValue.alertPopup(0, message: "1Password failed to fill into webview.")
            }
        }
    }
    
    //function to load Google search
    func searchPressed() {
        if(slideViewValue.searchEngines == 0) {
            slideViewValue.searchEngines = 1
            //slideViewValue.alertPopup(3, message: "Your search engine was changed to Bing")
            self.view.makeToast("Bing It On!", duration: 0.8, position: CGPoint(x: self.view.frame.size.width/2, y: UIScreen.mainScreen().bounds.height-70))
        } else {
            slideViewValue.searchEngines = 0
            //slideViewValue.alertPopup(3, message: "Your search engine was changed to Google")
            self.view.makeToast("Let's Google it!", duration: 0.8, position: CGPoint(x: self.view.frame.size.width/2, y: UIScreen.mainScreen().bounds.height-70))
        }
    }
    
    //add slash to urlfield
    func addSlash() {
        urlField.text = urlField.text! + "/"
    }
    
    //function to hide keyboard
    func hideKeyboard() {
        self.view.endEditing(true)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
        
        NSURLCache.sharedURLCache().removeAllCachedResponses()
    }
}
