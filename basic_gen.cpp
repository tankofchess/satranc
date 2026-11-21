#include <bits/stdc++.h>
using namespace std;

// K+V vs K veya K+R vs K için kesin DTM tablosu.
// index = (((wk*64 + bk)*64 + ps)*2 + stm); stm 0=beyaz, 1=siyah.
static const int N = 64*64*64*2;
static vector<uint8_t> res(N, 0), rem(N, 0), legalW(N, 0);
static bool isQueen;

inline int idx(int wk,int bk,int ps,int stm){ return (((wk*64+bk)*64+ps)*2 + stm); }
inline int f(int s){ return s & 7; }
inline int r(int s){ return s >> 3; }
inline bool adj(int a,int b){ return abs(f(a)-f(b))<=1 && abs(r(a)-r(b))<=1; }
inline bool overlapOk(int wk,int bk,int ps){
  return wk!=bk && wk!=ps && bk!=ps && !adj(wk,bk);
}

inline bool rayAttack(int ps,int target,int wk,int bk){
  int df=f(target)-f(ps), dr=r(target)-r(ps);
  bool sameRank = dr==0 && df!=0;
  bool sameFile = df==0 && dr!=0;
  bool sameDiag = abs(df)==abs(dr) && df!=0;
  if(!(sameRank||sameFile||(isQueen&&sameDiag))) return false;
  int sf = (df>0)-(df<0);
  int sr = (dr>0)-(dr<0);
  int x=f(ps)+sf, y=r(ps)+sr;
  while(x!=f(target) || y!=r(target)){
    int s=y*8+x;
    if(s==wk || s==bk) return false;
    x+=sf; y+=sr;
  }
  return true;
}
inline bool attackedByWhite(int target,int wk,int ps,int bk){
  return adj(target,wk) || rayAttack(ps,target,wk,bk);
}

inline void genBlack(int wk,int bk,int ps, vector<int>& out){
  const int D[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
  for(auto&d:D){
    int x=f(bk)+d[0], y=r(bk)+d[1];
    if(x<0||x>7||y<0||y>7) continue;
    int nb=y*8+x;
    if(nb==wk) continue;
    if(adj(nb,wk)) continue;
    if(attackedByWhite(nb,wk,ps,nb)) continue; // eski sah karesi bosalir
    out.push_back(nb);
  }
}

int main(int argc,char**argv){
  if(argc<2){ fprintf(stderr,"kullanim: basic_gen q|r\n"); return 1; }
  isQueen = (argv[1][0]=='q');
  string outFile = isQueen ? "/tmp/opencode/kq.dat" : "/tmp/opencode/kr.dat";
  auto t0=chrono::steady_clock::now();

  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++) for(int ps=0;ps<64;ps++){
    if(!overlapOk(wk,bk,ps)) continue;
    legalW[idx(wk,bk,ps,0)] = !attackedByWhite(bk,wk,ps,bk) ? 1 : 0;
    vector<int> mv; genBlack(wk,bk,ps,mv);
    int i=idx(wk,bk,ps,1);
    rem[i]=(uint8_t)min(mv.size(),(size_t)255);
    if(mv.empty() && attackedByWhite(bk,wk,ps,bk)){
      res[i]=1;
    }
  }
  {
    vector<int> q; q.reserve(N);
    for(int i=0;i<N;i++) if(res[i]) q.push_back(i);
    cerr<<(isQueen?"KQ":"KR")<<" mates="<<q.size()<<"\n";
    size_t head=0;
    while(head<q.size()){
      int cur=q[head++];
      uint8_t d=res[cur];
      int stm=cur&1;
      int t=cur>>1;
      int ps=t&63; t>>=6;
      int bk=t&63; t>>=6;
      int wk=t&63;

      if(stm==1){
        // beyaz hamle etti
        const int D[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
        for(auto&dd:D){
          int x=f(wk)+dd[0], y=r(wk)+dd[1];
          if(x<0||x>7||y<0||y>7) continue;
          int owk=y*8+x;
          if(!overlapOk(owk,bk,ps)) continue;
          int pi=idx(owk,bk,ps,0);
          if(legalW[pi] && res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
        }
        const int RD[4][2]={{1,0},{-1,0},{0,1},{0,-1}};
        const int BD[4][2]={{1,1},{1,-1},{-1,1},{-1,-1}};
        const int QD[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
        const int (*dirs)[2] = isQueen ? QD : RD;
        int ndir = isQueen ? 8 : 4;
        for(int k=0;k<ndir;k++){
          int x=f(ps)+dirs[k][0], y=r(ps)+dirs[k][1];
          while(x>=0&&x<=7&&y>=0&&y<=7){
            int ops=y*8+x;
            if(ops==wk||ops==bk) break;
            int pi=idx(wk,bk,ops,0);
            if(legalW[pi] && res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
            x+=dirs[k][0]; y+=dirs[k][1];
          }
        }
      } else {
        // siyah hamle etti
        if(!attackedByWhite(bk,wk,ps,bk)){
          const int D[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
          for(auto&dd:D){
            int x=f(bk)+dd[0], y=r(bk)+dd[1];
            if(x<0||x>7||y<0||y>7) continue;
            int obk=y*8+x;
            if(!overlapOk(wk,obk,ps)) continue;
            int pi=idx(wk,obk,ps,1);
            if(res[pi]!=0 || rem[pi]==0) continue;
            rem[pi]--;
            if(rem[pi]==0){ res[pi]=d+1; q.push_back(pi); }
          }
        }
      }
    }
    cerr<<(isQueen?"KQ":"KR")<<" states="<<q.size()
        <<" time="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";
  }
  FILE* fp=fopen(outFile.c_str(),"wb");
  fwrite(res.data(),1,N,fp); fclose(fp);
  return 0;
}
