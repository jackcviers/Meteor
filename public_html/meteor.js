// Set domain at highest level
var domainparts = document.domain.split(".");
document.domain = domainparts[domainparts.length-2]+"."+domainparts[domainparts.length-1];

Function.prototype.bind = function(obj) {
	var method = this,
	temp = function() {
		return method.apply(obj, arguments);
	};
	return temp;
}
Function.prototype.andThen=function(g) {
	var f=this;
	var a=this.arguments
	return function(args) {
		f(a);g(args);
	}
};

function Meteor(instID) {

	this.transferDoc = false;
	this.pingtimer = false;
	this.updatepollfreqtimer = false;
	this.lastrequest = 0;
	this.recvtimes = [];
	this.MHostId = false;
	this.callback_process = function() {};
	this.callback_reset = function() {};
	this.callback_eof = function() {};
	this.callback_changemode = function() {};
	this.callback_statuschanged = function() {};
	this.persist = true;
	this.frameloadtimer = false;
	this.debugmode = false;
	this.subsurl = false;
	this.channels = {};

	// Documented public properties
	this.subdomain = "data";
	this.dynamicpageaddress = "push";
	this.smartpoll = true;
	this.pollfreq = 2000;
	this.minpollfreq = 2000;
	this.mode = "poll";
	this.polltimeout=30000;
	this.pingtimeout = 10000;
	this.maxmessages = 0;
	this.status = 0;

	/* Statuses:	0 = Uninitialised,
					1 = Loading stream,
					2 = Loading controller frame,
					3 = Controller frame timeout, retrying.
					4 = Controller frame loaded and ready
					5 = Receiving data
	*/

	this.instID = (typeof(instID) != "undefined") ? instID : 0;
	this.MHostId = Math.floor(Math.random()*100000000)+""+this.instID;
}

Meteor.instances = new Array();

Meteor.create = function(instID) {
	if (!instID) instID = Meteor.instances.length;
	Meteor.instances[instID] = new Meteor(instID);
	return Meteor.instances[instID];
}

Meteor.register = function(ifr) {
	instid = new String(ifr.window.frameElement.id);
	instid = instid.replace(/.*_([0-9]*)$/, "$1");
	ifr.p = this.instances[instid].process.bind(this.instances[instid]);
	ifr.r = this.instances[instid].reset.bind(this.instances[instid]);
	ifr.eof = this.instances[instid].eof.bind(this.instances[instid]);
	ifr.get = this.instances[instid].get.bind(this.instances[instid]);
	ifr.increasepolldelay = this.instances[instid].increasepolldelay.bind(this.instances[instid]);
	clearTimeout(this.instances[instid].frameloadtimer);
	this.instances[instid].setstatus(4);
	if (this.debugmode) console.log("Frame registered");
}

Meteor.reset = function(ifr) {
	instid = new String(ifr.window.frameElement.id);
	instid = instid.replace(/.*_([0-9]*)$/, "$1");
	this.instances[instid].reset();
}

Meteor.prototype.joinChannel = function(channelname, backtrack) {
	if (typeof(this.channels[channelname]) != "undefined") throw "Cannot join channel "+channelname+": already subscribed";
	this.channels[channelname] = {backtrack:backtrack, lastmsgreceived:0};
	if (this.debugmode) console.log("Joined channel "+channelname+", channel list follows");
	if (this.debugmode) console.log(this.channels);
	if (this.status != 0) this.start();
}

Meteor.prototype.leaveChannel = function(channelname) {
	if (typeof(this.channels[channelname]) == "undefined") throw "Cannot leave channel "+channelname+": not subscribed";
	delete this.channels[channelname];
	if (this.status != 0) this.start();
}

Meteor.prototype.start = function() {
	this.persist = (this.maxmessages)?1:0;
	this.smartpoll = (this.smartpoll)?1:0;
	this.mode = (this.mode=="stream")?"stream":"poll";
	if (!this.subdomain || this.channels.length) throw "Channel or Meteor subdomain host not specified";
	this.stop();
	var now = new Date();
	var t = now.getTime();
	this.setstatus(1);
	var surl = "http://" + this.subdomain + "." + location.hostname + "/" + this.dynamicpageaddress + "?id=" + this.MHostId;
	if (this.maxmessages && !this.persist) surl += "&maxmessages=" + this.maxmessages;
	for (var c in this.channels) {
		surl += "&channel="+c;
		if (this.channels[c].lastmsgreceived >= 0) {
			surl += "&restartfrom="+this.channels[c].lastmsgreceived;
		} else if (this.channels[c].backtrack > 0) {
			surl += "&backtrack="+this.channels[c].backtrack;
		} else if (this.channels[c].backtrack < 0 || isNaN(this.channels[c].backtrack)) {
			surl += "&restartfrom=";
		}
	}
	this.subsurl = surl;
	if (this.mode=="stream") {
		this.createIframe(this.subsurl);
		var f = this.pollmode.bind(this);
		clearTimeout(this.pingtimer);
		this.pingtimer = setTimeout(f, this.pingtimeout);

	} else {
		this.createIframe("http://"+this.subdomain+"."+location.hostname+"/poll.html");
		this.recvtimes[0] = t;
		if (this.updatepollfreqtimer) clearTimeout(this.updatepollfreqtimer);
		this.updatepollfreqtimer = setInterval(this.updatepollfreq.bind(this), 2500);
	}
	this.lastrequest = t;
}

Meteor.prototype.createIframe = function(url) {
	if (document.all) {
		this.transferDoc = new ActiveXObject("htmlfile");
		this.transferDoc.open();
		this.transferDoc.write("<html>");
		this.transferDoc.write("<script>document.domain=\""+(document.domain)+"\";</"+"script>");
		this.transferDoc.write("</html>");
		var selfref = this;
		this.transferDoc.parentWindow.Meteor = Meteor;
		this.transferDoc.close();
		var ifrDiv = this.transferDoc.createElement("div");
		this.transferDoc.appendChild(ifrDiv);
		ifrDiv.innerHTML = "<iframe id=\"meteorframe_"+this.instID+"\" src=\""+url+"\" style=\"display: none;\"></iframe>";
	} else {
		var ifr = document.createElement("IFRAME");
		ifr.style.width = "10px";
		ifr.style.height = "10px";
		ifr.style.border = "none";
		ifr.style.position = "absolute";
		ifr.style.top = "-10px";
		ifr.style.marginTop = "-10px";
		ifr.style.zIndex = "-20";
		ifr.setAttribute("id", "meteorframe_"+this.instID);
		ifr.Meteor = Meteor;
		var innerifr = document.createElement("IFRAME");
		innerifr.setAttribute("src", url);
		innerifr.setAttribute("id", "meteorinnerframe_"+this.instID);
		ifr.appendChild(innerifr);
		document.body.appendChild(ifr);
	}
	if (this.debugmode) console.log("Loading URL '"+url+"' into frame...");
	var f = this.frameloadtimeout.bind(this);
	this.frameloadtimer = setTimeout(f, 5000);
}

Meteor.prototype.stop = function() {
	if (typeof(this.transferDoc)=="object") {
		this.transferDoc = false;
	}
	if (document.getElementById("meteorframe_"+this.instID)) {
		document.getElementById("meteorframe_"+this.instID).src="about:blank";
		document.body.removeChild(document.getElementById("meteorframe_"+this.instID));
	}
	if (!isNaN(this.pingtimer)) clearTimeout(this.pingtimer);
	if (!isNaN(this.updatepollfreqtimer)) clearTimeout(this.updatepollfreqtimer);
	if (!isNaN(this.frameloadtimer)) clearTimeout(this.frameloadtimer);
	this.setstatus(0);
}

Meteor.prototype.pollmode = function() {
	if (this.debugmode) console.log("Ping timeout");
	this.mode="poll";
	this.start();
	this.callback_changemode("poll");
	this.lastpingtime = false;
}

Meteor.prototype.process = function(id, channel, data) {
	if (id == -1) {
		if (this.debugmode) console.log("Ping");
		this.ping();
	} else if (typeof(this.channels[channel]) != "undefined" && id > this.channels[channel].lastmsgreceived) {
		if (this.debugmode) console.log("Message "+id+" received on channel "+channel+" (last id on channel: "+this.channels[channel].lastmsgreceived+")\n"+data);
		this.callback_process(data);
		this.channels[channel].lastmsgreceived = id;
		if (this.mode=="poll") {
			var now = new Date();
			var t = now.getTime();
			this.recvtimes[this.recvtimes.length] = t;
			while (this.recvtimes.length > 5) this.recvtimes.shift();
		}
	}
	this.setstatus(5);
}

Meteor.prototype.ping = function() {
	if (this.mode=="stream" && this.pingtimer) {
		clearTimeout(this.pingtimer);
		var f = this.pollmode.bind(this);
		this.pingtimer = setTimeout(f, this.pingtimeout);
		var now = new Date();
		this.lastpingtime = now.getTime();
	}
	this.setstatus(5);
}

Meteor.prototype.reset = function() {
	if (this.debugmode) console.log("Stream reset");
	var now = new Date();
	var t = now.getTime();
	var x = this.pollfreq - (t-this.lastrequest);
	if (x < 10) x = 10;
	this.ping();
	this.callback_reset();
	setTimeout(this.start.bind(this), x);
}

Meteor.prototype.eof = function() {
	this.callback_eof();
}

Meteor.prototype.get = function(varname) {
	eval("var a = this."+varname+";");
	if (typeof(a) == "undefined") throw "Cannot get value of "+varname;
	return a;
}

Meteor.prototype.increasepolldelay = function() {
	this.pollfreq *= 2;
}

Meteor.prototype.updatepollfreq = function() {
	if (this.smartpoll) {
		var now = new Date();
		var t = now.getTime();
		var avg = 0;
		for (var i=1; i<this.recvtimes.length; i++) {
			var x = (this.recvtimes[i]-this.recvtimes[i-1]);
			avg += (x>60000)? 60000 : x;
		}
		x = (t-this.recvtimes[this.recvtimes.length-1]);
		avg += (x>180000)? 180000 : x;
		avg /= this.recvtimes.length;
		if ((avg/3) < this.pollfreq && (avg/3) >= this.minpollfreq) this.pollfreq = Math.ceil(this.pollfreq*0.9);
		if ((avg/3) > this.pollfreq) this.pollfreq = Math.floor(this.pollfreq*1.05);
	}
}

Meteor.prototype.registerEventCallback = function(evt, funcRef) {
	if (evt=="process") {
		this.callback_process = (this.callback_process).andThen(funcRef);
	} else if (evt=="reset") {
		this.callback_reset = (this.callback_reset).andThen(funcRef);
	} else if (evt=="eof") {
		this.callback_eof = (this.callback_eof).andThen(funcRef);
	} else if (evt=="changemode") {
		this.callback_changemode = (this.callback_changemode).andThen(funcRef);
	} else if (evt=="changestatus") {
		this.callback_statuschanged = (this.callback_statuschanged).andThen(funcRef);
	}
}

Meteor.prototype.frameloadtimeout = function() {
	if (this.debugmode) console.log("Frame load timeout");
	if (this.frameloadtimer) clearTimeout(this.frameloadtimer);
	this.setstatus(3);
	setTimeout(this.start.bind(this), 5000);
}
Meteor.prototype.setstatus = function(newstatus) {
	if (this.status != newstatus) {
		this.status = newstatus;
		this.callback_statuschanged(newstatus);
	}
}

Meteor.createCookie = function(name,value,days) {
	if (days) {
		var date = new Date();
		date.setTime(date.getTime()+(days*24*60*60*1000));
		var expires = "; expires="+date.toGMTString();
	}
	else var expires = "";
	document.cookie = name+"="+value+expires+"; path=/";
}

Meteor.readCookie = function(name) {
	var nameEQ = name + "=";
	var ca = document.cookie.split(';');
	for(var i=0;i < ca.length;i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') c = c.substring(1,c.length);
		if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
	}
	return null;
}

Meteor.eraseCookie = function(name) {
	createCookie(name,"",-1);
}