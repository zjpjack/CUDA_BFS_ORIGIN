#include<iostream>
#include<fstream>
#include<stdio.h>
#include<stdlib.h>
#include<string>
//#include"bfs_kernel.cu"
using namespace std;
#include"bfs_kernel.cu"

const int MAX_THREADS_PER_BLOCK = 256;
char* infile = NULL;

void
usage(char* prog_name, const char* more) {
    cerr << more;
    cerr << "usage: " << prog_name << " input_file "<<endl;
    exit(0);
}

void
parse_args(int argc, char** argv) {
    for (int i = 0; i < argc; i++) {
        if (argv[i][0] == '-') {
            switch(argv[i][1]) {
                case 'i':
                    if (i == argc - 1) {
                        usage(argv[0], "Infile missing");
                    }
                    infile = argv[i + 1];
                    i++;
                    break;
            }
        }
    }
}

void bfsGraph(char* filename, int start_position) {
    int nb_nodes;
    ifstream finput;
    finput.open(filename, ios::in | ios::binary);

    //Read number of nodes on 4 bytes
    finput.read((char*)&nb_nodes, 4);
    if (start_position < 0 || start_position > nb_nodes) {
        return;
    }

    //Read cumulative degrees
    int* degrees = new int[nb_nodes];
    finput.read((char*)degrees, nb_nodes * 4);
    int* starting = new int[nb_nodes];
    memset(starting, 0, sizeof(int) * nb_nodes);
    for (int i = 1; i < nb_nodes; i++) {
        starting[i] = degrees[i - 1];
    }

    //Read links 
    int nb_links = degrees[nb_nodes - 1];
    int* links = new int[nb_links];
    finput.read((char*)links, nb_links * 4);
    finput.close();

    //Assign number of blocks and threads of each block we will use
    int num_of_blocks = 1;
    int num_of_threads_per_block = nb_nodes;
    if (nb_nodes > MAX_THREADS_PER_BLOCK) {
        num_of_blocks =
            (int)ceil((double)nb_nodes/(double)MAX_THREADS_PER_BLOCK);
        num_of_threads_per_block = MAX_THREADS_PER_BLOCK;
    }

    //allocate host memory
    Node* h_graph_nodes = (Node*) malloc(sizeof(Node) * nb_nodes);
    bool* h_graph_level = (bool*) malloc(sizeof(bool) * nb_nodes);
    bool* h_graph_visited = (bool*) malloc(sizeof(bool) * nb_nodes);

    //initialize the memory of nodes
    h_graph_nodes[0].starting = 0;
    h_graph_nodes[0].no_of_edges = degrees[0];
    h_graph_level[0] = false;
    h_graph_visited[0] = false;
    for (unsigned int i = 1; i < nb_nodes; i++) {
        h_graph_nodes[i].starting = starting[i];
        h_graph_nodes[i].no_of_edges = degrees[i] - degrees[i-1];
        h_graph_level[i] = false;
        h_graph_visited[i] = false;
    }
    h_graph_level[start_position] = true;

    //Copy node list to cuda memory
    Node* d_graph_nodes;
    cudaMalloc((void**)&d_graph_nodes, sizeof(Node) * nb_nodes);
    cudaMemcpy(d_graph_nodes, h_graph_nodes, sizeof(Node) *
            nb_nodes,cudaMemcpyHostToDevice);

    //Copy the edge list to device memory
    int* d_edge_list;
    cudaMalloc((void**)&d_edge_list, sizeof(int) * nb_links);
    cudaMemcpy(d_edge_list, links, sizeof(int) * nb_links,
            cudaMemcpyHostToDevice);

    //Copy the visited array to device memory
    bool* d_graph_visited;
    cudaMalloc((void**)&d_graph_visited, sizeof(bool) * nb_nodes);
    cudaMemcpy(d_graph_visited, h_graph_visited, sizeof(bool) *
            nb_nodes, cudaMemcpyHostToDevice);
    //test1<<<1, nb_nodes>>>(d_graph_visited, nb_nodes);
    //cudaMemcpy(h_graph_visited, d_graph_visited, sizeof(bool) *
    //        nb_nodes, cudaMemcpyDeviceToHost);
    //for (int i = 0; i < nb_nodes; i++) {
    //    cout<<"visited:"<<h_graph_visited[i]<<endl;
    //}

    //Copy the level to device memory
    bool* d_graph_level;
    cudaMalloc((void**)&d_graph_level, sizeof(bool) * nb_nodes);
    cudaMemcpy(d_graph_level, h_graph_level, sizeof(bool) * nb_nodes,
            cudaMemcpyHostToDevice);

    //allocate memory for the result on host
    int* h_cost = (int*)malloc(sizeof(int) * nb_nodes);
    for (int i = 0; i < nb_nodes; i++) {
        h_cost[i] = -1;
    }
    h_cost[start_position] = 0;

    //allocate device memory for result
    int* d_cost;
    cudaMalloc((void**)&d_cost, sizeof(int) * nb_nodes);
    cudaMemcpy(d_cost, h_cost, sizeof(int) * nb_nodes,
            cudaMemcpyHostToDevice);

    //allocate device memory for nb_nodes
    //int* d_nb_nodes;
    //cudaMalloc((void**)&d_nb_nodes, sizeof(int));
    //cudaMemcpy(d_nb_nodes, &nb_nodes, sizeof(int),
    //        cudaMemcpyHostToDevice);

    //make a bool to check if the execution is over
    bool* d_over;
    cudaMalloc((void**)&d_over, sizeof(bool));
    bool stop;
    //cout<<"no of links : "<<nb_links<<endl;
    //for ( int i = 0; i < nb_links; i++) {
    //    cout<<links[i]<<endl;
    //}
    //cout<<"blocks num : " << num_of_blocks<<endl;
    //dim3 grid(num_of_blocks, 1, 1);
    //dim3 threads(num_of_threads_per_block, 1, 1);
    do {
        stop = false;
        cudaMemcpy(d_over, &stop, sizeof(bool),
                cudaMemcpyHostToDevice);
        bfs_kernel<<<num_of_blocks,
            num_of_threads_per_block>>>(d_graph_nodes, d_edge_list,
                    d_graph_level, d_graph_visited, d_cost, d_over,
                    nb_nodes);
        cudaThreadSynchronize();
        //cudaMemcpy(&nb_nodes, d_nb_nodes, sizeof(int),
        //        cudaMemcpyDeviceToHost);
        //cout<<"new node num : "<<nb_nodes<<endl;
        cudaMemcpy(&stop, d_over, sizeof(bool),
                cudaMemcpyDeviceToHost);
        cout<<"stop : "<<stop<<endl;
    } while(stop);

    cout << "success!" <<endl;
    //cout<<h_graph_level[0]<<endl;
    //for (int i = 0; i < nb_nodes; i++) {
    //    cout<<h_graph_nodes[i].no_of_edges<<endl;
    //}
    cudaMemcpy(h_cost, d_cost, sizeof(int) * nb_nodes,
            cudaMemcpyDeviceToHost);
    //Store the result into a file
    FILE* fpo = fopen("result.txt", "w");
    for (int i = 0; i < nb_nodes; i++) {
        fprintf(fpo, "(%d) cost:%d\n", i, h_cost[i]);
    }
    test<<<num_of_blocks, num_of_threads_per_block>>>(d_graph_nodes,
            nb_nodes);
    cudaMemcpy(h_graph_nodes, d_graph_nodes, sizeof(Node)*nb_nodes,
            cudaMemcpyDeviceToHost);
    //for (int i = 0; i < nb_nodes; i++) {
    //    cout<<"new starting: "<<h_graph_nodes[i].starting<<endl;
    //}
    fclose(fpo);

    //cleanup memory
    free(h_graph_nodes);
    free(links);
    free(h_graph_level);
    free(h_graph_visited);
    free(h_cost);
    cudaFree(d_graph_nodes);
    cudaFree(d_edge_list);
    cudaFree(d_graph_level);
    cudaFree(d_graph_visited);
    cudaFree(d_cost);
}

int main(int argc, char** argv) {
    parse_args(argc, argv);
    bfsGraph(infile, 0);
    return 0;
}
