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

	this.lastmsgreceived = -1;
	this.transferDoc = false;
	this.pingtimer = false;
	this.updatepollfreqtimer = false;
	this.lastrequest = 0;
	this.recvtimes = new Array();
	this.MHostId = false;
	this.callback_process = function() {};
	this.callback_reset = function() {};
	this.callback_eof = function() {};
	this.callback_changemode = function() {};
	this.callback_statuschanged = function() {};
	this.persist = true;
	this.frameloadtimer = false;
	this.frameurl = false;

	// Documented public properties
	this.channel = false;
	this.subdomain = "data";
	this.dynamicpageaddress = "push";
	this.backtrack = 0;
	this.smartpoll = true;
	this.pollfreq = 2000;
	this.minpollfreq = 2000;
	this.mode = "stream";
	this.polltimeout=30000;
	this.maxmessages=0;
	this.pingtimeout = 10000;
	this.status = 0;

	/* Statuses:	0 = Uninitialised,
					1 = Loading stream,
					2 = Loading controller frame,
					3 = Controller frame timeout, retrying every 5 seconds
					4 = Controller frame loaded and ready
					5 = Receiving data
	*/

	// Set or retrieve host id.  Cookie takes this form:
	// MeteorID=123:6356353/124:098320454;
	var MeteIds = Meteor.readCookie("MeteorID");
	var regex1 = new RegExp("^([0-9\:\/M]+\/)*"+instID+"\:([^\/]+)(\/[0-9\:\/M]+)*$");
	var regex2 = new RegExp("^([0-9\:\/M]+\/)*M\:([^\/]+)(\/[0-9\:\/M]+)*$");
	if (typeof(instID) == "Number" && regex1.exec(MeteIds)) {
		this.MHostId = ma[2];
	} else if (typeof(instID) == "Number") {
		this.MHostId = Math.floor(Math.random()*1000000);
		var newcookie = (MeteIds)?MeteIds+"/":"";
		newcookie += instID+":"+this.MHostId;
		Meteor.createCookie("MeteorID", newcookie);
	} else if (ma = regex2.exec(MeteIds)) {
		this.MHostId = ma[2];
	} else {
		this.MHostId = Math.floor(Math.random()*1000000);
		var newcookie = (MeteIds)?MeteIds+"/":"";
		newcookie += "M:"+this.MHostId;
		Meteor.createCookie("MeteorID", newcookie);
	}
	this.instID = (typeof(instID) != "undefined") ? instID : 0;
}

Meteor.instances = new Array();
Meteor.servertimeoffset = 0;

Meteor.create = function(instID) {
	if (!instID) instID = 0;
	Meteor.instances[instID] = new Meteor(instID);
	return Meteor.instances[instID];
}

Meteor.register = function(ifr) {
	instid = new String(ifr.window.frameElement.id);
	instid = instid.replace("meteorframe_", "");
	ifr.p = this.instances[instid].process.bind(this.instances[instid]);
	ifr.r = this.instances[instid].reset.bind(this.instances[instid]);
	ifr.eof = this.instances[instid].eof.bind(this.instances[instid]);
	ifr.get = this.instances[instid].get.bind(this.instances[instid]);
	ifr.increasepolldelay = this.instances[instid].increasepolldelay.bind(this.instances[instid]);
	clearTimeout(this.instances[instid].frameloadtimer);
	this.instances[instid].setstatus(4);
}

Meteor.setServerTime = function(timestamp) {
	var now = new Date();
	var clienttime = (now.getTime() / 1000);
	Meteor.servertimeoffset = timestamp - clienttime;
}

Meteor.prototype.start = function() {
	this.persist = (this.maxmessages)?1:0;
	this.smartpoll = (this.smartpoll)?1:0;
	this.mode = (this.mode=="stream")?"stream":"poll";
	if (!this.subdomain || !this.channel) throw "Channel or Meteor subdomain host not specified";
	var now = new Date();
	var t = now.getTime();
	if (typeof(this.transferDoc)=="object") {
		this.transferDoc.open();
		this.transferDoc.close();
		delete this.transferDoc;
	}
	if (document.getElementById("meteorframe_"+this.instID)) {
		document.body.removeChild(document.getElementById("meteorframe_"+this.instID));
	}
	if (this.mode=="stream") {
		if (document.all) {
			this.setstatus(1);
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
			var url = "http://"+this.subdomain+"."+location.hostname+"/"+this.dynamicpageaddress+"?channel="+this.channel+"&id="+this.MHostId;
			if (this.lastmsgreceived >= 0) {
				url += "&restartfrom="+this.lastmsgreceived;
			} else if (this.backtrack > 0) {
				url += "&backtrack="+this.backtrack;
			} else if (this.backtrack < 0 || isNaN(this.backtrack)) {
				url += "&restartfrom=";
			}
			ifrDiv.innerHTML = "<iframe id=\"meteorframe_"+this.instID+"\" src=\""+url+"&nocache="+t+"\" style=\"display: none;\"></iframe>";
		} else {
			var ifr = document.createElement("IFRAME");
			ifr.style.width = "10px";
			ifr.style.height = "10px";
			ifr.style.border = "none";
			ifr.style.position = "absolute";
			ifr.style.top = "-10px";
			ifr.style.marginTop = "-10px";
			ifr.style.zIndex = "-20";
			ifr.id = "meteorframe_"+this.instID;
			document.body.appendChild(ifr);
			this.frameurl = "http://"+this.subdomain+"."+location.hostname+"/stream.html";
			this.frameload();
		}
		var f = this.pollmode.bind(this);
		clearTimeout(this.pingtimer);
		this.pingtimer = setTimeout(f, this.pingtimeout);

	} else {
		var ifr = document.createElement("IFRAME");
		ifr.style.width = "10px";
		ifr.style.height = "10px";
		ifr.style.border = "none";
		if (document.all) {
			ifr.style.display = "none";
		} else {
			ifr.style.position = "absolute";
			ifr.style.marginTop = "-10px";
			ifr.style.zIndex = "-20";
		}
		ifr.id = "meteorframe_"+this.instID;
		document.body.appendChild(ifr);
		this.frameurl = "http://"+this.subdomain+"."+location.hostname+"/poll.html";
		this.frameload();
		this.recvtimes[0] = t;
		if (this.updatepollfreqtimer) clearTimeout(this.updatepollfreqtimer);
		this.updatepollfreqtimer = setInterval(this.updatepollfreq.bind(this), 2500);
	}
	this.lastrequest = t;
}

Meteor.prototype.pollmode = function() {
	this.mode="poll";
	this.start();
	this.callback_changemode("poll");
	this.lastpingtime = false;
}

Meteor.prototype.process = function(id, data) {
	if (id > this.lastmsgreceived) {
		this.callback_process(data);
		if (id != -1) this.lastmsgreceived = id;
		if (this.mode=="poll") {
			var now = new Date();
			var t = now.getTime();
			this.recvtimes[this.recvtimes.length] = t;
			while (this.recvtimes.length > 5) this.recvtimes.shift();
		}
	} else if (id == -1) {
		this.ping();
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

Meteor.prototype.frameload = function() {
	this.setstatus(2);
	if (document.getElementById("meteorframe_"+this.instID)) {
		var f = this.frameloadtimeout.bind(this);
		this.frameloadtimer = setTimeout(f, 5000);
		document.getElementById("meteorframe_"+this.instID).src = "about:blank";
		setTimeout(this.doloadurl.bind(this), 100);
	}
}
Meteor.prototype.doloadurl = function() {
	var now = new Date();
	var t = now.getTime();
	document.getElementById("meteorframe_"+this.instID).src = this.frameurl+"?nocache="+t;
}
Meteor.prototype.frameloadtimeout = function() {
	if (this.frameloadtimer) clearTimeout(this.frameloadtimer);
	this.setstatus(3);
	this.frameload();
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