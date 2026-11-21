#include <bits/stdc++.h>
using namespace std;

static const int N = 33554432; // 64*64*64*64*2
static vector<uint8_t> res(N, 0), rem(N, 0), legalW(N, 0);

inline int idx(int wk,int bk,int bs,int ns,int stm){
  return ((((wk*64 + bk)*64 + bs)*64 + ns)*2 + stm);
}
inline int f(int s){ return s & 7; }
inline int r(int s){ return s >> 3; }
inline bool adj(int a,int b){ return abs(f(a)-f(b))<=1 && abs(r(a)-r(b))<=1; }
inline bool sameDiag(int a,int b){ return abs(f(a)-f(b))==abs(r(a)-r(b)); }

inline bool bishopAttack(int bs,int target,int wk,int bk,int ns){
  if(!sameDiag(bs,target)) return false;
  int df = f(target)>f(bs)?1:-1;
  int dr = r(target)>r(bs)?1:-1;
  int x=f(bs)+df, y=r(bs)+dr;
  while(x!=f(target) || y!=r(target)){
    int s=y*8+x;
    if(s==wk || s==bk || s==ns) return false;
    x+=df; y+=dr;
  }
  return true;
}
inline bool knightAttack(int ns,int target){
  int df=abs(f(ns)-f(target)), dr=abs(r(ns)-r(target));
  return (df==1&&dr==2)||(df==2&&dr==1);
}
inline bool attackedByWhite(int target,int wk,int bs,int ns,int bk){
  if(adj(target,wk)) return true;
  if(bishopAttack(bs,target,wk,bk,ns)) return true;
  if(knightAttack(ns,target)) return true;
  return false;
}
inline bool overlapOk(int wk,int bk,int bs,int ns){
  if(wk==bk||wk==bs||wk==ns||bk==bs||bk==ns||bs==ns) return false;
  if(adj(wk,bk)) return false;
  return true;
}
inline bool valid(int wk,int bk,int bs,int ns,int stm){
  if(!overlapOk(wk,bk,bs,ns)) return false;
  if(stm==0){ // white to move: black king not in check
    if(attackedByWhite(bk,wk,bs,ns,bk)) return false;
  }
  return true;
}

struct Move { int wk,bk,bs,ns; };

inline void genWhite(const Move& m, vector<Move>& out){
  const int D[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
  for(auto&d:D){
    int x=f(m.wk)+d[0], y=r(m.wk)+d[1];
    if(x<0||x>7||y<0||y>7) continue;
    int nw=y*8+x;
    if(!overlapOk(nw,m.bk,m.bs,m.ns)) continue;
    out.push_back({nw,m.bk,m.bs,m.ns});
  }
  const int BD[4][2]={{1,1},{1,-1},{-1,1},{-1,-1}};
  for(auto&d:BD){
    int x=f(m.bs), y=r(m.bs);
    while(true){
      x+=d[0]; y+=d[1];
      if(x<0||x>7||y<0||y>7) break;
      int nb=y*8+x;
      if(nb==m.wk||nb==m.bk||nb==m.ns) break;
      out.push_back({m.wk,m.bk,nb,m.ns});
    }
  }
  const int ND[8][2]={{1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2}};
  for(auto&d:ND){
    int x=f(m.ns)+d[0], y=r(m.ns)+d[1];
    if(x<0||x>7||y<0||y>7) continue;
    int nn=y*8+x;
    if(nn==m.wk||nn==m.bk||nn==m.bs) continue;
    out.push_back({m.wk,m.bk,m.bs,nn});
  }
}

inline void genBlack(const Move& m, vector<Move>& out){
  const int D[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
  for(auto&d:D){
    int x=f(m.bk)+d[0], y=r(m.bk)+d[1];
    if(x<0||x>7||y<0||y>7) continue;
    int nb=y*8+x;
    if(nb==m.wk||nb==m.bs||nb==m.ns) continue;
    if(adj(nb,m.wk)) continue;
    if(attackedByWhite(nb,m.wk,m.bs,m.ns,nb)) continue;
    out.push_back({m.wk,nb,m.bs,m.ns});
  }
}

int main(){
  auto t0=chrono::steady_clock::now();
  vector<uint32_t> q; q.reserve(8000000);
  // initialize black-to-move states and terminal mates
  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++) for(int bs=0;bs<64;bs++) for(int ns=0;ns<64;ns++){
    if(!overlapOk(wk,bk,bs,ns)) continue;
    legalW[idx(wk,bk,bs,ns,0)] = !attackedByWhite(bk,wk,bs,ns,bk) ? 1 : 0;
    Move m{wk,bk,bs,ns};
    vector<Move> mv; genBlack(m,mv);
    int i=idx(wk,bk,bs,ns,1);
    rem[i]=(uint8_t)min(mv.size(),(size_t)255);
    if(mv.empty() && attackedByWhite(bk,wk,bs,ns,bk)){
      res[i]=1; q.push_back(i);
    }
  }
  cerr<<"mates="<<q.size()<<" init="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";

  size_t head=0;
  while(head<q.size()){
    int cur=q[head++];
    uint8_t d=res[cur];
    int stm=cur&1;
    int t=cur>>1;
    int ns=t&63; t>>=6;
    int bs=t&63; t>>=6;
    int bk=t&63; t>>=6;
    int wk=t&63;

    if(stm==1){
      // predecessors: white moved. Doğrudan yasal ata kontrolü.
      const int D[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
      // şah komşu kareden geldi
      for(auto&dd:D){
        int x=f(wk)+dd[0], y=r(wk)+dd[1];
        if(x<0||x>7||y<0||y>7) continue;
        int owk=y*8+x;
        if(!overlapOk(owk,bk,bs,ns)) continue;
        if(!legalW[idx(owk,bk,bs,ns,0)]) continue;
        int pi=idx(owk,bk,bs,ns,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
      // fil aynı çaprazdan geldi; dolu kareye kadar yürünür
      const int BD[4][2]={{1,1},{1,-1},{-1,1},{-1,-1}};
      for(auto&dd:BD){
        int x=f(bs)+dd[0], y=r(bs)+dd[1];
        while(x>=0&&x<=7&&y>=0&&y<=7){
          int obs=y*8+x;
          if(obs==wk||obs==bk||obs==ns) break;
          int pi=idx(wk,bk,obs,ns,0);
          if(legalW[pi] && res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
          x+=dd[0]; y+=dd[1];
        }
      }
      // at knight mesafesinden geldi
      const int ND[8][2]={{1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2}};
      for(auto&dd:ND){
        int x=f(ns)+dd[0], y=r(ns)+dd[1];
        if(x<0||x>7||y<0||y>7) continue;
        int ons=y*8+x;
        if(ons==wk||ons==bk||ons==bs) continue;
        int pi=idx(wk,bk,bs,ons,0);
        if(legalW[pi] && res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
    } else {
      // predecessors: black king moved
      const int D[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
      if(!attackedByWhite(bk,wk,bs,ns,bk)){
        for(auto&dd:D){
          int x=f(bk)+dd[0], y=r(bk)+dd[1];
          if(x<0||x>7||y<0||y>7) continue;
          int obk=y*8+x;
          if(!overlapOk(wk,obk,bs,ns)) continue;
          int pi=idx(wk,obk,bs,ns,1);
          if(res[pi]!=0 || rem[pi]==0) continue;
          rem[pi]--;
          if(rem[pi]==0){ res[pi]=d+1; q.push_back(pi); }
        }
      }
    }
  }
  cerr<<"states="<<q.size()<<" total="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";
  FILE* fp=fopen("/tmp/opencode/kbn.dat","wb");
  fwrite(res.data(),1,N,fp); fclose(fp);
  return 0;
}
