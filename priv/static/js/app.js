// define the tree view treeitem component
Vue.component('treeitem', {
  template: '#treeitem-template',
  props: {
    model: Object
  },
  data: function() {
    return {
      open: false
    }
  },
  computed: {
    isFolder: function() {
      return this.model.populate ||
             !isEmpty(this.model.tabledata) ||
             !isEmpty(this.model.children);
    }
  },
  methods: {
    toggle: function() {
      if(this.isFolder) {
        var isUninitialized = isEmpty(this.model.children) && isEmpty(this.model.tabledata);
        if(isUninitialized){
          // open is set to true in populate callback
          this.model.populate(this);
        }
        else{
          this.open = !this.open;
        }
      }
    },
    refresh: function() {
      this.model.populate(this);
    },
    isRefreshable: function(){
      return (typeof this.model.populate === 'function') &&
             (this.model.isloading === false);
    }
  }
})

// assume all and insync are both sorted
function getOutOfSyncReplicas(all, insync){
  var r = [];
  for(i = 0; i<all.length; ){
    for(j = 0; j<insync.length; ){
      if(all[i] == insync[j]){
        i++;
        j++;
      }
      else {
        r.push(all[i]);
        i++;
      }
    }
  }
  return r;
}

function makePartitionTableRow(p){
  var osr = getOutOfSyncReplicas(p.replicas.sort(), p.isr.sort());
  if (osr.length == 0){
    osr = '';
  }
  return [p.partition, p.leader, p.replicas, osr];
}

// normalize table data
function norm(tab) {
  var mapfun = function(v) {
    if(typeof v === 'object') return JSON.stringify(v);
    else return v;
  };
  return tab.map(function(arr) {return arr.map(mapfun);});
}

function makeTopicTreeNodeChildren(r){
  var ret =
    [ { treenodename: "partitions"
      , headers: ['partition', 'leader', 'replicas', 'out-of-sync-replicas']
      , tabledata: norm(r.partitions.map(makePartitionTableRow))
      }
    ];
  var config = r.config;
  if(config != null && Object.keys(config).length > 0){
    ret.push(
      { treenodename: "config"
      , tabledata: norm(Object.keys(config).map(function(k){return [k, config[k]];}))
      }
    );
  }
  return ret;
}

function isEmpty(d) {
  return !(d && d.length)
}

function makeKvRows(obj, keys) {
  var kv = function(key) {
    var val = obj[key];
    if(val == 'undefined'){
      val = '';
    }
    return [key, val];
  };
  return keys.map(kv);
}

function makeCgTableData(r) {
  var keys = ['leader', 'protocol', 'generation_id'];
  return makeKvRows(r, keys);
}

function makeCgMember(member) {
  var sub = member.subscription;
  var r =
    { treenodename: member.member_id
    , tabledata: makeKvRows(member, ['session_timeout', 'client_id', 'client_host'])
    , children: [
        { treenodename: 'subscription'
        , tabledata: [ ['version', sub.version]
                     , ['userdata', sub.userdata]
                     ]
        , children: [
            {treenodename: 'topics',
             children: sub.topics.map(function(t){return {treenodename: t}})}
          ]
        }
      ]
    };
  return r;
}

function formatTs(Ts) {
  var date = new Date(Ts);
  var hours = date.getHours();
  var minutes = date.getMinutes();
  var seconds = date.getSeconds();
  minutes = minutes < 10 ? '0'+minutes : minutes;
  var strTime = hours + ':' + minutes + ':' + seconds;
  var day = date.getDate(),
  day = day < 10 ? '0' + day : day;
  var mon = date.getMonth()+1,
  mon = mon < 10 ? '0' + mon : mon;
  return date.getFullYear() + '-' + mon + '-' + day + "  " + strTime;
}

function makeCgOffsetsRow(p, keys) {
  return keys.map(function(k){
    var val = p[k.name];
    if(k.fmtfun) {
      val = k.fmtfun(val);
    }
    return val;
  });
}

function makeCgTreeNodeChildren(r) {
  var res = []
  if(r.members && r.members.length){
    var membersNode =
      { treenodename: 'members'
      , children: r.members.map(makeCgMember)
      };
    res.push(membersNode);
  }
  if(r.partitions && r.partitions.length){
    var keys =
      [ {name: 'topic'}
      , {name: 'partition'}
      , {name: 'offset'}
      , {name: 'lagging'}
      , {name: 'commit_time', fmtfun: formatTs}
      , {name: 'expire_time', fmtfun: formatTs}
      , {name: 'metadata'}
      ];
    var offsetsNode =
      { treenodename: "offsets"
      , headers: keys.map(function(k) {return k.name;})
      , tabledata: r.partitions.map(function(p) {
                      if(!p.high_wm_offset || p.high_wm_offset < p.offset) {
                        // high watermark offset and committed offset are
                        // collected in two different (async) flow
                        // show '?' in case high watermark offset is not found
                        // or being delayed
                        p.lagging = '?'
                      }
                      else {
                        p.lagging = p.high_wm_offset - p.offset;
                      }
                      return makeCgOffsetsRow(p, keys);
                    })
      };
    res.push(offsetsNode);
  }
  return res;
}

var app = new Vue(
{ el: '#app'
, data:
  { tabBrokers: false
  , tabTopics: false
  , tabCgs: false
  , brokers: [{treenodename: "loading brokers ..."}]
  , topics: [{treenodename: "loading topics ..."}]
  , cgs: [{treenodename: "loading consumer groups  ..."}]
  , last_req: ""
  , last_rsp: ""
  , last_rsp_ok: true
  }
, methods:
  { hideAllTabs() {
      this.tabBrokers = false;
      this.tabTopics  = false;
      this.tabCgs     = false;
    }
  , showTopics: function() {
      this.hideAllTabs();
      this.tabTopics = true
      var http = this.$http;
      var uri = '/api/v1/topics';
      this.last_req = uri;
      var theapp = this;
      http.get(uri).then(
        function(response) { // ok
          this.last_rsp = JSON.stringify(response.data, null, 2);
          this.last_rsp_ok = true;
          var mapfun = function(topicname) {
            var ret =
              { treenodename: topicname
              , isloading: true
              , populate: function(self) {
                  var req = '/api/v1/topics/' + topicname;
                  theapp.last_req = req;
                  http.get(req).then(
                    function(r) {
                      theapp.last_rsp = JSON.stringify(r.data, null, 2);
                      theapp.last_rsp_ok = true;
                      self.model.children = makeTopicTreeNodeChildren(r.data);
                      self.model.isloading = false;
                      self.open = true;
                    },
                    function(r) {
                      theapp.last_rsp = JSON.stringify(r, null, 2);
                      theapp.last_rsp_ok = false;
                      self.model.children = [];
                      self.model.isloading = false;
                      self.open = false;
                    }
                  );
                }
              };
            return ret;
          };
          this.topics = response.data.sort().map(mapfun);
        },
        function(response){ // error
          this.last_rsp = JSON.stringify(response, null, 2);
          this.last_rsp_ok = true;
          this.topics = [];
        });
    }
  , showCgs: function() {
      this.hideAllTabs();
      this.tabCgs = true
      var http = this.$http;
      var uri = '/api/v1/consumers';
      this.last_req = uri;
      var theapp = this;
      http.get(uri).then(
        function(response) { // ok
          this.last_rsp = JSON.stringify(response.data, null, 2);
          this.last_rsp_ok = true;
          var mapfun = function(cgid) {
            var ret =
              { treenodename: cgid
              , isloading: true
              , populate: function(self) {
                  var req = 'api/v1/consumers/' + cgid;
                  theapp.last_req = req;
                  http.get(req).then(
                    function(r) { // ok
                      theapp.last_rsp = JSON.stringify(r.data, null, 2);
                      theapp.last_rsp_ok = true;
                      self.model.tabledata = norm(makeCgTableData(r.data));
                      self.model.children = makeCgTreeNodeChildren(r.data);
                      self.model.isloading = false;
                      self.open = true;
                    },
                    function(r) { // error
                      console.log(r);
                      theapp.last_rsp = JSON.stringify(r, null, 2);
                      theapp.last_rsp_ok = false;
                      self.model.children = [];
                      self.model.isloading = false;
                      self.open = false;
                    }
                  );
                }
              }
            return ret;
          };
          this.cgs = response.data.sort().map(mapfun);
        },
        function(response) { // error
          this.last_rsp = JSON.stringify(response, null, 2);
          this.last_rsp_ok = false;
          this.cgs = [];
        }
      );
    }
  , showBrokers : function() {
      this.hideAllTabs();
      this.tabBrokers = true;
      var http = this.$http;
      var uri = '/api/v1/brokers';
      this.last_req = uri;
      http.get(uri).then(
        function(response) {
          this.last_rsp = JSON.stringify(response.data, null, 2);
          this.last_rsp_ok = true;
          var mapfun = function(broker){
            var res =
              { treenodename: broker.host+':'+broker.port
              , tabledata: broker.endpoints.map(function(ep){return [ep]})
              };
            return res;
          }
          this.brokers = response.data.map(mapfun);
        },
        function(response) {
          this.last_rsp = JSON.stringify(response, null, 2);
          this.last_rsp_ok = false;
          this.brokers = [];
        }
      );
    }
  }
});
// default tab
app.showTopics();

